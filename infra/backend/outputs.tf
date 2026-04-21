output "chat_api_url" {
  description = "HTTP API invoke URL"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "chat_table_name" {
  description = "DynamoDB table name for chat history"
  value       = aws_dynamodb_table.chat.name
}

output "openai_secret_arn" {
  description = "Secrets Manager ARN for OpenAI API key"
  value       = aws_secretsmanager_secret.openai_api_key.arn
}
