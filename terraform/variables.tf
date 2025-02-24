
variable "aws_profile" {
  type    = string
  default = ""
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "prod_account" {
  type = string
}

variable "custom_domain" {
  type = string
}


variable "s3_bucket" {
  description = "(Optional, Forces new resource) The name of the bucket. If omitted, Terraform will assign a random, unique name."
  type        = string
  default     = null
}

variable "s3_website_root" {
  description = "the default root object of your s3 website. To be used by the cloudfront distribution."
  type        = string
  default     = "index.html"
}

variable "lambda_function_name" {
  type = string
}

variable "ddb_table" {
  type = string
}


