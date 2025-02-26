from os import environ

from boto3 import resource
import json

#  DynamoDBClass is used for function and testing

LAMBDA_DYNAMODB_RESOURCE = { "resource" : resource('dynamodb', region_name='us-east-1'), 
                              "table_name" : environ.get("DYNAMODB_TABLE_NAME","NONE") }



class LambdaDynamoDBClass:
    """
    AWS DynamoDB Resource Class
    """
    def __init__(self, lambda_dynamodb_resource):
        """
        Initialize a DynamoDB Resource
        """
        self.resource = lambda_dynamodb_resource["resource"]
        self.table_name = lambda_dynamodb_resource["table_name"]
        self.table = self.resource.Table(self.table_name)


def lambda_handler(event, context):

    global LAMBDA_DYNAMODB_RESOURCE
    
    dynamo_resource_class = LambdaDynamoDBClass(LAMBDA_DYNAMODB_RESOURCE)

    return update_visitor_count(dynamo_resource_class)


def update_visitor_count(dynamo_db: LambdaDynamoDBClass):
    
    try:
        ddb_count_update = dynamo_db.table.update_item(
            Key={'visit': 'visit_info'},
            UpdateExpression='ADD visit_count :inc',
            ExpressionAttributeValues={':inc': 1},
            ReturnValues='UPDATED_NEW'
        )

        body = {
            "visit_count": int(ddb_count_update['Attributes']['visit_count'])
        }
        status_code = 200

    except KeyError as index_error:
        body = {
            "error": f"Not Found: {str(index_error)}"
        }
        status_code = 404
    except Exception as other_error:               
        body = {
            "error": f"Error: {str(other_error)}"
        }
        status_code = 500
    finally:
        return {
            "statusCode": status_code,
            "body": json.dumps(body)
        }

