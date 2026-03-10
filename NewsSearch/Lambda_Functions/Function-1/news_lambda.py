import json
import urllib.request
import boto3
import os
import re
import urllib.parse
from datetime import datetime, timedelta, timezone

# Initialize clients
s3_client = boto3.client("s3")
translate = boto3.client("translate")
lambda_client = boto3.client("lambda")

# Read environment variables
bucket_name = os.environ["BUCKET_NAME"]
API_KEY = "c82a0b5c312a4610bd8701b8d242796e"
TARGET_LANGUAGE = "en"
ddb_create_lambda_function_name = os.environ.get("DDB_CREATE_LAMBDA_FUNCTION_NAME")

if not ddb_create_lambda_function_name:
    raise ValueError("DDB_CREATE_LAMBDA_FUNCTION_NAME environment variable is not set.")

def sanitize_filename(name):
    return re.sub(r'[^a-zA-Z0-9_-]', '_', name)[:50]

def lambda_handler(event, context):
    try:
        print("Received event:", json.dumps(event))

        # Handle API Gateway GET requests
        query_params = event.get("queryStringParameters", {})
        topic = query_params.get("query", "Finance")  # required
        source_lang = query_params.get("language", "en")  # optional

        from_date = (datetime.now(timezone.utc) - timedelta(days=30)).strftime("%Y-%m-%d")
        query = urllib.parse.quote(topic)
        url = (
            f"https://newsapi.org/v2/everything?q={query}"
            f"&from={from_date}&sortBy=popularity&apiKey={API_KEY}&language={source_lang}"
        )

        with urllib.request.urlopen(url) as response:
            data = json.load(response)

        articles = data.get("articles", [])
        uploaded = 0

        for i, article in enumerate(articles):
            title = article.get("title", f"untitled_{i}")
            content = article.get("content", "")
            published_at = article.get("publishedAt", "")
            article_url = article.get("url", "")

            if not content:
                continue

            try:
                translated = translate.translate_text(
                    Text=content,
                    SourceLanguageCode=source_lang,
                    TargetLanguageCode=TARGET_LANGUAGE
                )["TranslatedText"]
            except Exception as e:
                print(f"Translation error: {e}")
                translated = ""

            article_data = {
                "id": str(i + 1),
                "title": title,
                "content": content,
                "translatedContent": translated,
                "publishedDate": published_at,
                "url": article_url,
                "topic": topic,
                "language": source_lang
            }

            filename = sanitize_filename(title) + ".json"
            file_path = f"/tmp/{filename}"
            with open(file_path, "w") as file:
                json.dump(article_data, file, indent=2)

            s3_client.upload_file(file_path, bucket_name, f"news/{filename}")
            uploaded += 1

        ddb_event = {
            "topic": topic,
            "uploadedCount": uploaded,
            "bucket": bucket_name,
            "message": f"{uploaded} articles uploaded for topic '{topic}' from language '{source_lang}'"
        }

        ddb_response = lambda_client.invoke(
            FunctionName=ddb_create_lambda_function_name,
            InvocationType="RequestResponse",
            Payload=json.dumps(ddb_event)
        )

        ddb_payload = json.loads(ddb_response['Payload'].read())

        return {
            "statusCode": 200,
            "headers": {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
                "Access-Control-Allow-Methods": "OPTIONS,GET"
            },
            "body": json.dumps({
                "message": f"{uploaded} articles uploaded and processed",
                "ddbResponse": ddb_payload
            })
        }

    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            "statusCode": 500,
            "headers": {
                "Access-Control-Allow-Origin": "*"
            },
            "body": json.dumps({"error": "Internal Server Error"})
        }