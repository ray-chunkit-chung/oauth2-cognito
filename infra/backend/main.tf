locals {
  lambda_zip_path    = "${path.module}/../../backend/dist/lambda.zip"
  openai_secret_name = "${var.project_prefix}/backend/openai-api-key"
}

data "aws_ssm_parameter" "cognito_user_pool_id" {
  name = "/${var.project_prefix}/frontend/cognito-user-pool-id"
}

data "aws_ssm_parameter" "cognito_user_pool_client_id" {
  name = "/${var.project_prefix}/frontend/cognito-user-pool-client-id"
}

resource "aws_secretsmanager_secret" "openai_api_key" {
  name                    = local.openai_secret_name
  description             = "OpenAI API key for ${var.project_prefix} backend"
  recovery_window_in_days = 0
}

resource "aws_dynamodb_table" "chat" {
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
  function_name = "${var.project_prefix}-chat-api"
  role          = aws_iam_role.chat_lambda.arn
  runtime       = "python3.13"
  handler       = "handler.lambda_handler"
  timeout       = 30
  memory_size   = 512

  filename         = local.lambda_zip_path
  source_code_hash = filebase64sha256(local.lambda_zip_path)

  environment {
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
  name              = "/aws/lambda/${aws_lambda_function.chat_api.function_name}"
  retention_in_days = 14
}

resource "aws_apigatewayv2_api" "chat" {
  name          = "${var.project_prefix}-chat-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = [var.frontend_base_url, var.frontend_local_base_url]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.chat.id
  name             = "${var.project_prefix}-cognito-jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [data.aws_ssm_parameter.cognito_user_pool_client_id.value]
    issuer   = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${data.aws_ssm_parameter.cognito_user_pool_id.value}"
  }
}

resource "aws_apigatewayv2_integration" "chat_lambda" {
  api_id                 = aws_apigatewayv2_api.chat.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.chat_api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.chat.id
  route_key = "GET /chat/health"
  target    = "integrations/${aws_apigatewayv2_integration.chat_lambda.id}"
}

resource "aws_apigatewayv2_route" "list_sessions" {
  api_id             = aws_apigatewayv2_api.chat.id
  route_key          = "GET /chat/sessions"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.chat_lambda.id}"
}

resource "aws_apigatewayv2_route" "get_session" {
  api_id             = aws_apigatewayv2_api.chat.id
  route_key          = "GET /chat/sessions/{sessionId}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.chat_lambda.id}"
}

resource "aws_apigatewayv2_route" "post_message" {
  api_id             = aws_apigatewayv2_api.chat.id
  route_key          = "POST /chat/messages"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.chat_lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.chat.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.chat_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.chat.execution_arn}/*/*"
}

resource "aws_ssm_parameter" "chat_api_url" {
  name  = "/${var.project_prefix}/backend/chat-api-url"
  type  = "String"
  value = aws_apigatewayv2_stage.default.invoke_url
}

resource "aws_ssm_parameter" "openai_secret_arn" {
  name  = "/${var.project_prefix}/backend/openai-secret-arn"
  type  = "String"
  value = aws_secretsmanager_secret.openai_api_key.arn
}

resource "aws_ssm_parameter" "chat_table_name" {
  name  = "/${var.project_prefix}/backend/chat-table-name"
  type  = "String"
  value = aws_dynamodb_table.chat.name
}
