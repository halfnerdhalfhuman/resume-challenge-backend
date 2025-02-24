import os
from unittest import TestCase
from boto3 import resource
from moto import mock_aws

from app import LambdaDynamoDBClass 
from app import update_visitor_count
                  


@mock_aws
class TestUpdateVisitCount(TestCase):

    def setUp(self) -> None:
        os.environ['AWS_DEFAULT_REGION'] = 'us-east-1'
        os.environ['AWS_ACCESS_KEY_ID'] = 'testing'
        os.environ['AWS_SECRET_ACCESS_KEY'] = 'testing'
        os.environ['AWS_SECURITY_TOKEN'] = 'testing'
        os.environ['AWS_SESSION_TOKEN'] = 'testing'
        
        self.test_table_name = "test_visit_count"
        os.environ["DYNAMODB_TABLE_NAME"] = self.test_table_name

        self.dynamodb = resource("dynamodb", region_name="us-east-1")
        self.dynamodb.create_table(
            TableName=self.test_table_name,
            KeySchema=[{"AttributeName": "visit", "KeyType": "HASH"}],
            AttributeDefinitions=[{"AttributeName": "visit", "AttributeType": "S"}],
            BillingMode='PAY_PER_REQUEST'
        )
       
        mocked_dynamodb_resource = { "resource" : self.dynamodb,
                                        "table_name" : self.test_table_name}
        self.mocked_dynamodb_class = LambdaDynamoDBClass(mocked_dynamodb_resource)


    def test_update_visitor_count(self) -> None:

        test_initial_count = update_visitor_count(dynamo_db = self.mocked_dynamodb_class)
        self.assertEqual(int(test_initial_count["body"]["visit_count"]), 1)
        self.assertEqual(test_initial_count["statusCode"], 200)

        test_inc_count = update_visitor_count(dynamo_db = self.mocked_dynamodb_class)
        self.assertEqual(int(test_inc_count["body"]["visit_count"]), 2)
        self.assertEqual(test_inc_count["statusCode"], 200)

    def tearDown(self) -> None:
        self.mocked_dynamodb_class.table.delete()