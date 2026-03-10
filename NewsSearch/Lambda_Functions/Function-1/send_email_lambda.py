import boto3
import os

sns = boto3.client('sns')
topic_arn = os.environ['SNS_TOPIC_ARN']

def lambda_handler(event, context):
    topic = event.get("topic", "Unknown")
    results = event.get("results", {})
    overall = results.get("overallSentiment", "N/A")
    breakdown = results.get("breakdown", {})

    breakdown_text = "\n".join([f"- {k}: {v}%" for k, v in breakdown.items()])

    message = (
        f"Sentiment results for topic '{topic}':\n\n"
        f"Overall Sentiment: {overall}\n\n"
        f"Breakdown:\n{breakdown_text}"
    )

    response = sns.publish(
        TopicArn=topic_arn,
        Subject=f"Sentiment Report: {topic}",
        Message=message
    )

    return {
        "statusCode": 200,
        "body": f"Email published via SNS. Message ID: {response['MessageId']}"
    }

"""TEST
{
  "topic": "Climate Change",
  "results": {
    "overallSentiment": "NEUTRAL",
    "breakdown": {
      "POSITIVE": 30,
      "NEUTRAL": 50,
      "NEGATIVE": 20
    }
  }
}
"""