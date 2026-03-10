import boto3
import json
import os
from datetime import datetime

# Set up clients for Comprehend, DynamoDB, and Lambda.
comprehend = boto3.client('comprehend')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('COMBINED_DYNAMODB_TABLE')
lambda_client = boto3.client('lambda')

def lambda_handler(event, context):
    # Initialize sentiment counters.
    sentiment_counts = {"POSITIVE": 0, "NEGATIVE": 0, "NEUTRAL": 0, "MIXED": 0}

    # Scan the DynamoDB table for articles.
    response = table.scan()
    items = response['Items']

    # Process each article for sentiment analysis.
    for article in items:
        content = article.get('content', '')
        if not content.strip():  # Skip empty or whitespace-only content.
            continue

        # Use AWS Comprehend to detect sentiment.
        result = comprehend.detect_sentiment(Text=content, LanguageCode='en')
        sentiment = result.get('Sentiment')
        if sentiment in sentiment_counts:
            sentiment_counts[sentiment] += 1

    # Calculate sentiment percentages.
    total = sum(sentiment_counts.values())
    if total == 0:
        # If no valid content is found, prepare a simple message for SNS.
        analysis_result = {
            "overallSentiment": "N/A",
            "breakdown": sentiment_counts
        }
    else:
        percentages = {
            sentiment: round((count / total) * 100, 2)
            for sentiment, count in sentiment_counts.items()
        }
        analysis_result = {
            "overallSentiment": max(percentages, key=percentages.get),
            "breakdown": percentages
        }
        
    # Parse dates and find the most recent article
    most_recent_item = max(
        items,
        key=lambda item: datetime.fromisoformat(item["publishedDate"].replace("Z", "+00:00"))
    )

    # Extract topic from most recent article
    topic = most_recent_item.get("topic", "Unknown Topic")

    # Build the event for SNSLambda.
    sns_event = {
        "topic": topic,
        "results": analysis_result
    }
    
    # Synchronously invoke the SNS Lambda.
    sns_response = lambda_client.invoke(
        FunctionName="sendSentimentEmailViaSNS",
        InvocationType='RequestResponse',  # Synchronous invocation.
        Payload=json.dumps(sns_event)
    )  
    sns_response_payload = json.loads(sns_response['Payload'].read())

    return {
        "sns":sns_response_payload,
        "news": sns_event
    }