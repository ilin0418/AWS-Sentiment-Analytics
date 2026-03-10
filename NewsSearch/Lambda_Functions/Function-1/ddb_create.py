import boto3
import json
import os
from botocore.exceptions import ClientError

# Environment and constant definitions.
S3_BUCKET_NAME = os.environ['BUCKET_NAME']
DYNAMODB_TABLE_NAME = "COMBINED_DYNAMODB_TABLE"


def get_dynamodb_count(table):
    response = table.scan(Select='COUNT')
    return response['Count']


def clear_dynamodb_table(table):
    # Use a loop to handle paginated scan responses.
    while True:
        response = table.scan(ProjectionExpression='id')
        items = response.get('Items', [])
        if not items:
            break

        with table.batch_writer() as batch:
            for item in items:
                batch.delete_item(Key={'id': item['id']})

        # If there are no more items to scan, exit the loop.
        if 'LastEvaluatedKey' not in response:
            break


def lambda_handler(event, context):
    s3 = boto3.client('s3')
    dynamodb = boto3.resource('dynamodb')
    all_data = []

    # Retrieve all JSON files from S3.
    paginator = s3.get_paginator('list_objects_v2')
    for page in paginator.paginate(Bucket=S3_BUCKET_NAME):
        if 'Contents' in page:
            for obj in page['Contents']:
                if obj['Key'].endswith('.json'):
                    try:
                        response = s3.get_object(Bucket=S3_BUCKET_NAME, Key=obj['Key'])
                        file_data = json.loads(response['Body'].read().decode('utf-8'))

                        # Ensure file_data is in a list or a single dict.
                        if isinstance(file_data, list):
                            all_data.extend(file_data)
                        elif isinstance(file_data, dict):
                            all_data.append(file_data)
                        else:
                            raise ValueError(f"Unexpected JSON structure in {obj['Key']}")
                    except Exception as e:
                        print(f"Error processing file {obj['Key']}: {str(e)}")

    # Exit early if no JSON data found.
    if not all_data:
        return {'statusCode': 200, 'body': 'No JSON files found'}

    # Manage DynamoDB table.
    try:
        table = dynamodb.Table(DYNAMODB_TABLE_NAME)
        table_exists = True
        ddb_count = get_dynamodb_count(table)
    except ClientError as e:
        if e.response['Error']['Code'] == 'ResourceNotFoundException':
            try:
                table = dynamodb.create_table(
                    TableName=DYNAMODB_TABLE_NAME,
                    KeySchema=[{'AttributeName': 'id', 'KeyType': 'HASH'}],
                    AttributeDefinitions=[{'AttributeName': 'id', 'AttributeType': 'S'}],
                    BillingMode='PAY_PER_REQUEST'
                )
                table.wait_until_exists()
                table_exists = False
                ddb_count = 0
            except Exception as create_error:
                raise ValueError(f"Error creating DynamoDB table: {str(create_error)}")
        else:
            raise

    # Clear table if it isn't empty.
    if table_exists and ddb_count > 0:
        clear_dynamodb_table(table)

    # Filter out duplicate items based on the 'id'
    seen_ids = set()
    unique_data = []
    for item in all_data:
        item_id = str(item.get('id', ''))
        if item_id not in seen_ids:
            seen_ids.add(item_id)
            unique_data.append(item)

    # Batch write all unique items into the DynamoDB table.
    with table.batch_writer() as batch:
        for item in unique_data:
            batch.put_item(Item={
                'id': str(item.get('id', '')),
                'title': str(item.get('title', '')),
                'content': str(item.get('content', '')),
                'topic': str(item.get('topic', '')),
                'publishedDate': str(item.get('publishedDate', ''))
            })

    # Synchronously invoke the Comprehend Lambda. It is expected that this Lambda
    # performs sentiment analysis (using the newly populated DynamoDB data),
    # then calls the SNS Lambda, and ultimately returns the SNS response.
    lambda_client = boto3.client('lambda')
    try:
        comprehend_response = lambda_client.invoke(
            FunctionName='sentimentAnalysisLambda',  # Ensure this function name is correct.
            InvocationType='RequestResponse',
            Payload=json.dumps({})  # If you need to send payload, include it here
        )

        # Parse and return the payload from the Comprehend Lambda (the SNS response).
        comprehend_response_payload = json.loads(comprehend_response['Payload'].read())
        return comprehend_response_payload
    except ClientError as e:
        return {'statusCode': 500, 'body': f"Error invoking sentiment analysis lambda: {str(e)}"}
