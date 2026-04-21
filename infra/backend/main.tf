locals {
  lambda_zip_path    = "${path.module}/../../backend/dist/lambda.zip"
  openai_secret_name = "${var.project_prefix}/backend/openai-api-key"

  frontend_allowed_origins = [var.frontend_base_url, var.frontend_local_base_url]

  public_chat_routes = toset([
    "GET /chat/health",
  ])

  protected_chat_routes = toset([
    "GET /chat/sessions",
    "GET /chat/sessions/{sessionId}",
    "POST /chat/messages",
  ])

  backend_ssm_parameters = {
    "chat-api-url"      = aws_apigatewayv2_stage.default.invoke_url
    "openai-secret-arn" = aws_secretsmanager_secret.openai_api_key.arn
    "chat-table-name"   = aws_dynamodb_table.chat.name
  }
}

moved {
  from = aws_apigatewayv2_route.health
  to   = aws_apigatewayv2_route.public["GET /chat/health"]
}

moved {
  from = aws_apigatewayv2_route.list_sessions
  to   = aws_apigatewayv2_route.protected["GET /chat/sessions"]
}

moved {
  from = aws_apigatewayv2_route.get_session
  to   = aws_apigatewayv2_route.protected["GET /chat/sessions/{sessionId}"]
}

moved {
  from = aws_apigatewayv2_route.post_message
  to   = aws_apigatewayv2_route.protected["POST /chat/messages"]
}

moved {
  from = aws_ssm_parameter.chat_api_url
  to   = aws_ssm_parameter.backend["chat-api-url"]
}

moved {
  from = aws_ssm_parameter.openai_secret_arn
  to   = aws_ssm_parameter.backend["openai-secret-arn"]
}

moved {
  from = aws_ssm_parameter.chat_table_name
  to   = aws_ssm_parameter.backend["chat-table-name"]
}

# ------------------------------------------------------------------------------
# Cognito Config Inputs (from frontend stack)
# ------------------------------------------------------------------------------

data "aws_ssm_parameter" "cognito_user_pool_id" {
  name = "/${var.project_prefix}/frontend/cognito-user-pool-id"
}

data "aws_ssm_parameter" "cognito_user_pool_client_id" {
  name = "/${var.project_prefix}/frontend/cognito-user-pool-client-id"
}

# ------------------------------------------------------------------------------
# Secrets, Data Store, and Lambda Runtime
# ------------------------------------------------------------------------------

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

# ------------------------------------------------------------------------------
# API Gateway (HTTP API + JWT Auth)
# ------------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "chat" {
  name          = "${var.project_prefix}-chat-http-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = local.frontend_allowed_origins
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

resource "aws_apigatewayv2_route" "public" {
  for_each = local.public_chat_routes

  api_id    = aws_apigatewayv2_api.chat.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.chat_lambda.id}"
}

resource "aws_apigatewayv2_route" "protected" {
  for_each = local.protected_chat_routes

  api_id             = aws_apigatewayv2_api.chat.id
  route_key          = each.value
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

# ------------------------------------------------------------------------------
# Backend Parameters (for app and CI/CD)
# ------------------------------------------------------------------------------
resource "aws_ssm_parameter" "backend" {
  for_each = local.backend_ssm_parameters

  name  = "/${var.project_prefix}/backend/${each.key}"
  type  = "String"
  value = each.value
}
