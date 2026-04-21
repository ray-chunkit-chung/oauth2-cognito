# locals are reusable values to avoid repeating the same string in many resources.
locals {
  # Lambda deployment package built by backend/build.sh.
  lambda_zip_path = "${path.module}/../../backend/dist/lambda.zip"
  # Secret name only. CI/CD writes the actual API key value later.
  openai_secret_name = "${var.project_prefix}/backend/openai-api-key"

  # Browser origins allowed to call this API through CORS.
  frontend_allowed_origins = [var.frontend_base_url, var.frontend_local_base_url]
}

# ------------------------------------------------------------------------------
# Cognito Config Inputs (from frontend stack)
# ------------------------------------------------------------------------------

data "aws_ssm_parameter" "cognito_user_pool_id" {
  # User pool ID from frontend stack.
  name = "/${var.project_prefix}/frontend/cognito-user-pool-id"
}

data "aws_ssm_parameter" "cognito_user_pool_client_id" {
  # App client ID used as JWT audience.
  name = "/${var.project_prefix}/frontend/cognito-user-pool-client-id"
}

# ------------------------------------------------------------------------------
# Secrets, Data Store, and Lambda Runtime
# ------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "openai_api_key" {
  # Stores metadata for the OpenAI key. Secret value is managed outside Terraform.
  name                    = local.openai_secret_name
  description             = "OpenAI API key for ${var.project_prefix} backend"
  recovery_window_in_days = 0
}

resource "aws_dynamodb_table" "chat" {
  # Simple single-table design: pk/sk stores sessions and messages.
  name         = "${var.project_prefix}-chat"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }
}

resource "aws_iam_role" "chat_lambda" {
  # Trust policy: allows the Lambda service to assume this role.
  name = "${var.project_prefix}-chat-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "chat_lambda" {
  # Permission policy: defines what the Lambda can access at runtime.
  name = "${var.project_prefix}-chat-lambda-policy"
  role = aws_iam_role.chat_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "ChatTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:BatchWriteItem",
          "dynamodb:DeleteItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.chat.arn
      },
      {
        Sid    = "OpenAISecretRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.openai_api_key.arn
      }
    ]
  })
}

resource "aws_lambda_function" "chat_api" {
  # The API runtime: API Gateway forwards all chat routes to this function.
  function_name = "${var.project_prefix}-chat-api"
  role          = aws_iam_role.chat_lambda.arn
  runtime       = "python3.13"
  handler       = "handler.lambda_handler"
  timeout       = 30
  memory_size   = 512

  filename         = local.lambda_zip_path
  source_code_hash = filebase64sha256(local.lambda_zip_path)

  environment {
    # Runtime config injected from infrastructure values.
    variables = {
      CHAT_TABLE_NAME      = aws_dynamodb_table.chat.name
      OPENAI_SECRET_ARN    = aws_secretsmanager_secret.openai_api_key.arn
      OPENAI_MODEL         = var.openai_model
      OPENAI_SYSTEM_PROMPT = "You are a helpful assistant."
      MAX_INPUT_CHARACTERS = "4000"
    }
  }
}

resource "aws_cloudwatch_log_group" "chat_api" {
  # Keep logs for 14 days instead of the service default retention.
  name              = "/aws/lambda/${aws_lambda_function.chat_api.function_name}"
  retention_in_days = 14
}

# ------------------------------------------------------------------------------
# API Gateway (HTTP API + JWT Auth)
# ------------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "chat" {
  # Creates the HTTP API container that holds routes, integrations, and auth settings.
  name          = "${var.project_prefix}-chat-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    # Frontend origins allowed by browsers to call this API.
    allow_origins = local.frontend_allowed_origins
    # HTTP methods browsers can use for cross-origin requests.
    allow_methods = ["GET", "POST", "DELETE", "OPTIONS"]
    # Request headers browsers are allowed to send.
    allow_headers = ["authorization", "content-type"]
    # Cache preflight (OPTIONS) response for 1 hour to reduce repeated checks.
    max_age = 3600
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  # Verifies Cognito JWTs before API Gateway forwards protected requests to Lambda.
  api_id          = aws_apigatewayv2_api.chat.id
  name            = "${var.project_prefix}-cognito-jwt"
  authorizer_type = "JWT"
  # Read token from Authorization header (Bearer <token>).
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    # Token must be issued for this app client (aud claim).
    audience = [data.aws_ssm_parameter.cognito_user_pool_client_id.value]
    # Token must come from this Cognito user pool (iss claim).
    issuer = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${data.aws_ssm_parameter.cognito_user_pool_id.value}"
  }
}

resource "aws_apigatewayv2_integration" "chat_lambda" {
  # One Lambda proxy integration reused by every route.
  # API Gateway passes method/path/body to Lambda, and Lambda returns HTTP response data.
  api_id                 = aws_apigatewayv2_api.chat.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.chat_api.invoke_arn
  payload_format_version = "2.0"
}

# Define each route explicitly.
resource "aws_apigatewayv2_route" "health" {
  # Public health check endpoint.
  # Used by smoke tests/monitoring to confirm backend is reachable.
  # No JWT required because it should be callable before user login.
  api_id    = aws_apigatewayv2_api.chat.id
  route_key = "GET /chat/health"
  target    = "integrations/${aws_apigatewayv2_integration.chat_lambda.id}"
}

resource "aws_apigatewayv2_route" "list_sessions" {
  # Returns chat session list for the authenticated user.
  # API Gateway validates JWT first; invalid/expired tokens are rejected before Lambda runs.
  api_id             = aws_apigatewayv2_api.chat.id
  route_key          = "GET /chat/sessions"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.chat_lambda.id}"
}

resource "aws_apigatewayv2_route" "get_session" {
  # Returns one chat session identified by {sessionId} in the URL path.
  # JWT is required, and Lambda should enforce that the session belongs to this user.
  api_id             = aws_apigatewayv2_api.chat.id
  route_key          = "GET /chat/sessions/{sessionId}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.chat_lambda.id}"
}

resource "aws_apigatewayv2_route" "delete_session" {
  # Deletes one chat session and all messages under that session.
  # JWT is required so users can only delete their own chat history.
  api_id             = aws_apigatewayv2_api.chat.id
  route_key          = "DELETE /chat/sessions/{sessionId}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.chat_lambda.id}"
}

resource "aws_apigatewayv2_route" "post_message" {
  # Accepts a user prompt and returns assistant output.
  # Typical Lambda flow: validate input -> write user message -> call model -> write assistant message.
  api_id             = aws_apigatewayv2_api.chat.id
  route_key          = "POST /chat/messages"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.chat_lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  # $default stage means the invoke URL has no extra stage path segment.
  api_id      = aws_apigatewayv2_api.chat.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  # Allow this API Gateway to invoke the Lambda function.
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.chat.execution_arn}/*/*"
}

# ------------------------------------------------------------------------------
# Backend Parameters (for app and CI/CD)
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "chat_api_url" {
  # Used by CI/CD and clients to discover the backend base URL.
  name  = "/${var.project_prefix}/backend/chat-api-url"
  type  = "String"
  value = aws_apigatewayv2_stage.default.invoke_url
}

resource "aws_ssm_parameter" "openai_secret_arn" {
  # Used by CI/CD jobs that update the OpenAI secret value.
  name  = "/${var.project_prefix}/backend/openai-secret-arn"
  type  = "String"
  value = aws_secretsmanager_secret.openai_api_key.arn
}

resource "aws_ssm_parameter" "chat_table_name" {
  # Used by jobs and scripts that need the DynamoDB table name.
  name  = "/${var.project_prefix}/backend/chat-table-name"
  type  = "String"
  value = aws_dynamodb_table.chat.name
}
