output "chat_api_url" {
  description = "Canonical backend API URL"
  value       = "https://${aws_apigatewayv2_domain_name.chat_api_custom.domain_name}"
}

output "chat_table_name" {
  description = "DynamoDB table name for chat history"
  value       = aws_dynamodb_table.chat.name
}

output "openai_secret_arn" {
  description = "Secrets Manager ARN for OpenAI API key"
  value       = aws_secretsmanager_secret.openai_api_key.arn
}
