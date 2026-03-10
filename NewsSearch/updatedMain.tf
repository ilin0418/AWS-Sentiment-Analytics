provider "aws" {
    region = "us-east-1"
    access_key = "REPLACE"
    secret_key = "REPLACE"
}

# DynamoDB Tables
resource "aws_dynamodb_table" "articles" {
  name         = "Articles"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name = "articlesDynamo"
  }
}

resource "aws_dynamodb_table" "data_table" {
  name         = "COMBINED_DYNAMODB_TABLE"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "id"
    type = "S"
  }

  hash_key = "id"

  tags = {
    Name        = "Lambda Data Table"
    Environment = "production"
  }

  lifecycle {
    prevent_destroy = false
  }
}

# S3 Bucket
resource "aws_s3_bucket" "article_storage" {
  bucket = "team1-sentiment-articles-${random_id.unique_id.hex}"
  force_destroy = true                                                        #Force delete bucket when terraform destroy

  tags = {
    name = "articlesS3"
  }
}

# Random ID for S3 bucket name uniqueness
resource "random_id" "unique_id" {
  byte_length = 4
}

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "block_access" {
  bucket = aws_s3_bucket.article_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM Roles
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# IAM Role Policy Attachments
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "s3_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "comprehend_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/ComprehendFullAccess"
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name = "LambdaDynamoDBAccess"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Full permissions for interacting with DynamoDB tables
      {
        Action   = ["dynamodb:*"],
        Effect   = "Allow",
        Resource = [
          aws_dynamodb_table.articles.arn,
          aws_dynamodb_table.data_table.arn,
          "${aws_dynamodb_table.articles.arn}/*",
          "${aws_dynamodb_table.data_table.arn}/*"
        ]
      },
      {
      Action = ["lambda:InvokeFunction"],
      Effect = "Allow",
      Resource = [
        "arn:aws:lambda:us-east-1:*:function:ddb-create-handler",
        aws_lambda_function.sentiment_analysis.arn,
        aws_lambda_function.send_sns_email.arn,
        aws_lambda_function.news_lambda.arn
      ]
    }

    ]
  })
}

resource "aws_iam_role_policy_attachment" "translate_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/TranslateReadOnly"
}



# Lambda Functions
resource "aws_lambda_function" "news_search" {
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.article_storage.bucket
      DDB_CREATE_LAMBDA_FUNCTION_NAME = aws_lambda_function.ddb_create.function_name
    }
  }

  depends_on = [
    aws_iam_role_policy.lambda_permissions,
    aws_iam_role_policy_attachment.translate_access,
    aws_lambda_function.sentiment_analysis,
    aws_lambda_function.send_sns_email
  ]
  
  function_name    = "searchNews-lambda"
  handler          = "news_lambda.lambda_handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_exec_role.arn
  filename         = "${path.module}/Lambda_Functions/Function-1/news_lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/Lambda_Functions/Function-1/news_lambda.zip")
  timeout          = 600
}

resource "aws_lambda_function" "sentiment_analysis" {
  function_name    = "sentimentAnalysisLambda"
  handler          = "comprehendLambdaDynamo.lambda_handler"  
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_exec_role.arn
  filename         = "${path.module}/Lambda_Functions/Function-1/comprehendLambdaDynamo.zip"
  source_code_hash = filebase64sha256("${path.module}/Lambda_Functions/Function-1/comprehendLambdaDynamo.zip")
  timeout       = 600
}

resource "aws_iam_role_policy_attachment" "dynamodb_read_access" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
}

resource "aws_lambda_function" "ddb_create" {
  filename      = "${path.module}/Lambda_Functions/Function-1/ddb_create.zip"
  function_name = "ddb-create-handler"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "ddb_create.lambda_handler"
  runtime       = "python3.11"
  timeout       = 600
  memory_size   = 512
  publish       = true
  source_code_hash = filebase64sha256("${path.module}/Lambda_Functions/Function-1/ddb_create.zip")
  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.data_table.name
      BUCKET_NAME         = aws_s3_bucket.article_storage.bucket
    }
  }

  depends_on = [
    aws_dynamodb_table.data_table
  ]
}

resource "aws_iam_role_policy" "allow_sentiment_to_invoke_news_search" {
  name = "AllowSentimentToInvokeNewsSearch"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = ["lambda:InvokeFunction"],
        Effect = "Allow",
        Resource = aws_lambda_function.news_search.arn
      }
    ]
  })
}

# Attach basic logging
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SNS Publish permission
resource "aws_iam_role_policy" "sns_publish" {
  name = "AllowSNSPublish"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = "sns:Publish",
      Resource = aws_sns_topic.sentiment_email.arn
    }]
  })
}

# SNS Topic for email
resource "aws_sns_topic" "sentiment_email" {
  name = "sentiment-email-topic"
}

# Lambda Function
resource "aws_lambda_function" "send_sns_email" {
  function_name    = "sendSentimentEmailViaSNS"
  filename         = "${path.module}/Lambda_Functions/Function-1/send_email_lambda.zip"
  handler          = "send_email_lambda.lambda_handler"
  runtime          = "python3.11"
  role             = aws_iam_role.lambda_exec_role.arn
  timeout          = 600
  source_code_hash = filebase64sha256("${path.module}/Lambda_Functions/Function-1/send_email_lambda.zip")

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.sentiment_email.arn
    }
  }

  depends_on = [
    aws_iam_role_policy.sns_publish
  ]
}

variable "email_list" {
  default = ["REPLACE"]
}

resource "aws_sns_topic_subscription" "email_subscribers" {
  for_each  = toset(var.email_list)
  topic_arn = aws_sns_topic.sentiment_email.arn
  protocol  = "email"
  endpoint  = each.key
}
