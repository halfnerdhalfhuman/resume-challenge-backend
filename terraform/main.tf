# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}


# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.ddb_state_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}


###############################################################################
# S3 Configuration
###############################################################################

resource "aws_s3_bucket" "website" {
  bucket = var.s3_bucket
}

resource "aws_s3_bucket_ownership_controls" "website" {
  bucket = aws_s3_bucket.website.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}
resource "aws_s3_bucket_acl" "website" {
  depends_on = [aws_s3_bucket_ownership_controls.website]

  bucket = aws_s3_bucket.website.id
  acl    = "private"
}

resource "aws_s3_bucket_policy" "allow_cloudfront" {
  bucket = aws_s3_bucket.website.id
  policy = data.aws_iam_policy_document.s3_website_bkt_policy.json
}

data "aws_iam_policy_document" "s3_website_bkt_policy" {
  version   = "2008-10-17"
  policy_id = "PolicyForCloudFrontPrivateContent"

  statement {
    sid     = "AllowCloudFrontServicePrincipal"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.website.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.website.arn]
    }
  }
}

###############################################################################
# Cloudfront Configuration
###############################################################################


resource "aws_cloudfront_origin_access_control" "website" {
  description                       = null
  name                              = "s3_oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


resource "aws_cloudfront_distribution" "website" {

  default_root_object = var.s3_website_root
  aliases             = [var.custom_domain]
  enabled             = true
  http_version        = "http2"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_All"
  retain_on_delete    = false
  wait_for_deployment = true
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # AWS Managed CachingDisabled Policy
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    smooth_streaming       = false
    target_origin_id       = aws_s3_bucket.website.bucket_regional_domain_name
    viewer_protocol_policy = "redirect-to-https"
  }
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
    origin_id                = aws_s3_bucket.website.bucket_regional_domain_name
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2021"
    acm_certificate_arn            = aws_acm_certificate.main.arn
    ssl_support_method             = "sni-only"
  }
  restrictions {
    geo_restriction {
      locations        = []
      restriction_type = "none"
    }
  }
}


###############################################################################
# Lambda Configuration
###############################################################################

resource "aws_lambda_function" "VisitorCounter" {
  architectures                  = ["x86_64"]
  code_signing_config_arn        = null
  description                    = ""
  filename                       = "../lambda-visitor-count/lambda_function_payload.zip"
  function_name                  = var.lambda_function_name
  handler                        = "app.lambda_handler"
  memory_size                    = 512
  package_type                   = "Zip"
  reserved_concurrent_executions = -1
  role                           = aws_iam_role.lambda.arn
  runtime                        = "python3.10"
  skip_destroy                   = false
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  tags = {
    "lambda-console:blueprint" = "microservice-http-endpoint-python"
  }
  tags_all = {
    "lambda-console:blueprint" = "microservice-http-endpoint-python"
  }
  timeout = 10
  ephemeral_storage {
    size = 512
  }
  logging_config {
    log_format = "Text"
    log_group  = "/aws/lambda/${var.lambda_function_name}"
  }
  tracing_config {
    mode = "PassThrough"
  }
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.visit_counter.id
    }
  }
}


data "archive_file" "lambda" {
  type        = "zip"
  source_file = "../lambda-visitor-count/app.py"
  output_path = "../lambda-visitor-count/lambda_function_payload.zip"
}



###############################################################################
# API Gateway Configuration
###############################################################################

resource "aws_apigatewayv2_api" "lambda" {
  api_key_selection_expression = "$request.header.x-api-key"
  description                  = "Created by AWS Lambda"
  disable_execute_api_endpoint = false

  name          = "${var.lambda_function_name}-API"
  protocol_type = "HTTP"

  route_selection_expression = "$request.method $request.path"

  cors_configuration {
    allow_credentials = false
    allow_headers     = ["content-type"]
    allow_methods     = ["GET"]
    allow_origins     = ["https://${aws_cloudfront_distribution.website.domain_name}", "https://${var.custom_domain}"]
    expose_headers    = []
    max_age           = 0
  }
}


resource "aws_apigatewayv2_deployment" "lambda" {
  api_id      = aws_apigatewayv2_api.lambda.id
  description = "Automatic deployment triggered by changes to the Api configuration"
  triggers    = null
  depends_on  = [aws_apigatewayv2_route.lambda]
}


resource "aws_apigatewayv2_route" "lambda" {
  api_id               = aws_apigatewayv2_api.lambda.id
  api_key_required     = false
  authorization_scopes = []
  authorization_type   = "NONE"
  request_models       = {}
  route_key            = "GET /${var.lambda_function_name}"
  target               = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}


resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.lambda.id
  connection_type        = "INTERNET"
  integration_method     = "POST"
  integration_type       = "AWS_PROXY"
  integration_uri        = "arn:aws:lambda:${var.aws_region}:${var.prod_account}:function:${var.lambda_function_name}"
  payload_format_version = "1.0"
  request_parameters     = {}
  request_templates      = {}
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id          = aws_apigatewayv2_api.lambda.id
  auto_deploy     = true
  description     = "Created by AWS Lambda"
  name            = "default"
  stage_variables = {}
  tags            = {}
  tags_all        = {}
  default_route_settings {
    data_trace_enabled       = false
    detailed_metrics_enabled = false
    logging_level            = null
    throttling_burst_limit   = 0
    throttling_rate_limit    = 0
  }
}



###############################################################################
# Route53 Configuration
###############################################################################

resource "aws_route53_zone" "main" {
  comment = "HostedZone created by Route53 Registrar"
  name    = var.custom_domain

}

resource "aws_route53_record" "main_cdn_AAAA" {
  name    = var.custom_domain
  type    = "AAAA"
  zone_id = aws_route53_zone.main.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
  }
}


resource "aws_route53_record" "main_cdn_A" {
  name    = var.custom_domain
  type    = "A"
  zone_id = aws_route53_zone.main.zone_id
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
  }
}


resource "aws_route53_record" "main_acm" {
  name    = "_6588faf31a68493e9c27bdc1883ce5bd.${var.custom_domain}"
  records = ["_c30295a431746b2d11f9633bfaf98171.zfyfvmchrl.acm-validations.aws."]
  ttl     = 300
  type    = "CNAME"
  zone_id = aws_route53_zone.main.zone_id
}






###############################################################################
# ACM Configuration
###############################################################################


resource "aws_acm_certificate" "main" {

  domain_name   = var.custom_domain
  key_algorithm = "RSA_2048"

  subject_alternative_names = ["*.${var.custom_domain}", var.custom_domain]
  validation_method         = "DNS"
  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}



###############################################################################
# DynamoDB Configuration
###############################################################################

resource "aws_dynamodb_table" "visit_counter" {
  billing_mode                = "PAY_PER_REQUEST"
  deletion_protection_enabled = false
  hash_key                    = "visit"
  name                        = var.ddb_table
  read_capacity               = 0
  stream_enabled              = false
  table_class                 = "STANDARD"
  write_capacity              = 0
  attribute {
    name = "visit"
    type = "S"
  }
  point_in_time_recovery {
    enabled = false
  }
  ttl {
    attribute_name = null
    enabled        = false
  }
}



###############################################################################
# IAM Configuration
###############################################################################

resource "aws_iam_service_linked_role" "apigateway" {
  aws_service_name = "ops.apigateway.amazonaws.com"
  description      = "Service-linked role for API Gateway"
}


resource "aws_iam_role" "lambda" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
  force_detach_policies = false
  max_session_duration  = 3600
  name                  = "DynamoLambdaAccess"
  path                  = "/service-role/"
}




resource "aws_iam_policy" "lambda_logs" {
  description = null
  name        = "AWSLambdaBasicExecutionRole-c40c659d-ffa8-4ac1-a59f-2d5b721bb8d8"
  name_prefix = null
  path        = "/service-role/"
  policy = jsonencode({
    Statement = [{
      Action   = "logs:CreateLogGroup"
      Effect   = "Allow"
      Resource = "arn:aws:logs:${var.aws_region}:${var.prod_account}:*"
      }, {
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Effect   = "Allow"
      Resource = ["arn:aws:logs:${var.aws_region}:${var.prod_account}:log-group:/aws/lambda/${var.lambda_function_name}:*"]
    }]
    Version = "2012-10-17"
  })
  tags     = {}
  tags_all = {}
}

resource "aws_iam_policy" "lambda_ddb" {
  description = null
  name        = "AWSLambdaMicroserviceExecutionRole-1edead9a-a1d0-4849-8cae-c0b4f3e54c6e"
  name_prefix = null
  path        = "/service-role/"
  policy = jsonencode({
    Statement = [{
      Action   = ["dynamodb:DeleteItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Scan", "dynamodb:UpdateItem"]
      Effect   = "Allow"
      Resource = "arn:aws:dynamodb:${var.aws_region}:${var.prod_account}:table/*"
    }]
    Version = "2012-10-17"
  })
  tags     = {}
  tags_all = {}
}


resource "aws_iam_role_policy_attachment" "ddb_attach" {
  policy_arn = aws_iam_policy.lambda_ddb.arn
  role       = aws_iam_role.lambda.name
}

resource "aws_iam_role_policy_attachment" "lambda_log_attach" {
  policy_arn = aws_iam_policy.lambda_logs.arn
  role       = aws_iam_role.lambda.name
}


# Github Actions Role / Policy

resource "aws_iam_openid_connect_provider" "github_actions" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  url             = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_role" "github_actions" {
  name                 = "GitHubAction-AssumeRoleWithAction"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:tlew19/*"
        }
      }
      Effect = "Allow"
      Principal = {
        Federated = "${aws_iam_openid_connect_provider.github_actions.arn}"
      }
    }]
    Version = "2012-10-17"
  })



}

resource "aws_iam_policy" "github_actions" {
  name = "GitHubActions"

  policy = jsonencode({
    Statement = [{
      Effect = "Allow"
      NotAction = [
        "organizations:*",
        "account:*"
      ]
      Resource = ["*"]
    }]
    Version = "2012-10-17"
  })
}



resource "aws_iam_role_policy_attachment" "github_actions" {
  policy_arn = aws_iam_policy.github_actions.arn
  role       = aws_iam_role.github_actions.name
}

