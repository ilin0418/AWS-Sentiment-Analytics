# IAM Role for Lambda Execution

locals {
    python_files = "${path.cwd}/Lambda_Functions"
}
data "archive_file" "zip_news_lambda_code" {
  type        = "zip"
  source_dir  = "${local.python_files}/Function-1/"
  output_path = "${local.python_files}/Function-1/news_lambda.zip" 
}

resource "aws_lambda_function" "news_lambda" {
  filename      = data.archive_file.zip_news_lambda_code.output_path
  function_name = "news_lambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "news_lambda.lambda_handler"
  runtime       = "python3.11"
  memory_size   = 500
  timeout       = 600

  environment {
    variables = {
      BUCKET_NAME                    = aws_s3_bucket.article_storage.bucket
      DDB_CREATE_LAMBDA_FUNCTION_NAME = aws_lambda_function.ddb_create.function_name
    }
  }
}

# Define API Gateway REST API
resource "aws_api_gateway_rest_api" "news" {
  name        = "news-api"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Define the /query resource
resource "aws_api_gateway_resource" "query" {
  rest_api_id = aws_api_gateway_rest_api.news.id
  parent_id   = aws_api_gateway_rest_api.news.root_resource_id
  path_part   = "query"
}

# CORS - OPTIONS Method (MOCK Integration)
resource "aws_api_gateway_method" "options_query" {
  rest_api_id   = aws_api_gateway_rest_api.news.id
  resource_id   = aws_api_gateway_resource.query.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "cors_mock" {
  rest_api_id = aws_api_gateway_rest_api.news.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.options_query.http_method
  integration_http_method = "OPTIONS"
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "cors_response" {
  rest_api_id = aws_api_gateway_rest_api.news.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.options_query.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
  
  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

}

resource "aws_api_gateway_integration_response" "cors_mock_response" {
  rest_api_id = aws_api_gateway_rest_api.news.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.options_query.http_method
  status_code = aws_api_gateway_method_response.cors_response.status_code

  depends_on = [aws_api_gateway_integration.cors_mock]

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Define the GET method
resource "aws_api_gateway_method" "get_query" {
  rest_api_id   = aws_api_gateway_rest_api.news.id
  resource_id   = aws_api_gateway_resource.query.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.querystring.query" = true
    "method.request.querystring.language" = false
  }
}

# Integration of GET with Lambda
resource "aws_api_gateway_integration" "lambda_get" {
  rest_api_id = aws_api_gateway_rest_api.news.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.get_query.http_method

  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri = aws_lambda_function.news_lambda.invoke_arn

  request_parameters = {
    "integration.request.querystring.query" = "method.request.querystring.query"
    "integration.request.querystring.language" = "method.request.querystring.language"
  }
}

resource "aws_api_gateway_method_response" "get_method_response" {
  rest_api_id = aws_api_gateway_rest_api.news.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.get_query.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true,
    "method.response.header.Access-Control-Allow-Methods" = true,
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "get_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.news.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.get_query.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'",
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'",
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  depends_on = [aws_api_gateway_method_response.get_method_response, aws_api_gateway_integration.lambda_get]
}

# Deploy API Gateway changes
resource "aws_api_gateway_deployment" "prod_deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_get,
    aws_api_gateway_integration.cors_mock,
    aws_lambda_permission.apigw_lambda
  ]
  rest_api_id = aws_api_gateway_rest_api.news.id
}

# Define API Gateway Stage (prod)
resource "aws_api_gateway_stage" "prod_stage" {
  rest_api_id   = aws_api_gateway_rest_api.news.id
  stage_name    = "prod"
  deployment_id = aws_api_gateway_deployment.prod_deployment.id
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.news_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  # More specific source ARN
  source_arn = "${aws_api_gateway_rest_api.news.execution_arn}/*/${aws_api_gateway_method.get_query.http_method}${aws_api_gateway_resource.query.path}"
}

# Output the Invoke URL
output "invoke_url" {
  value = "${aws_api_gateway_stage.prod_stage.invoke_url}/query"
}


locals {
  react_api_url = "${aws_api_gateway_stage.prod_stage.invoke_url}/query"
}

resource "aws_iam_role" "amplify_role" {
  name               = "amplify-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = ["amplify.us-east-1.amazonaws.com", "amplify.amazonaws.com"]
        }
        Action   = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_amplify_app" "my_app" {
  name       = "Amplify_test"
  repository = "https://github.com/ilin0418/AWS-Sentiment-Analytics"
  access_token = "REPLACE"

  iam_service_role_arn = aws_iam_role.amplify_role.arn


  //Configure the branch that Amplify will use
  build_spec = <<-EOT
      version: 1
      frontend:
        phases:
          preBuild:
            commands:
                - cd amplify
                - npm install
          build:
            commands:
                - echo "REACT_APP_API_URL=${local.react_api_url}" >> .env
                - npm run build
        artifacts:
            baseDirectory: amplify/build   
            files:
            - '**/*'
        cache:
          paths: 
            - node_modules/**/*
    EOT 
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.my_app.id
  branch_name = "main"
}
