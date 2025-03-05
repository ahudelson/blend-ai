output "api_url" {
  value       = "https://${aws_api_gateway_domain_name.blend_api_domain.domain_name}/blend"
  description = "The URL for the Blend API endpoint"
}

output "frontend_url" {
  value       = "https://${var.domain_name}"
  description = "The URL for the frontend application"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.frontend.id
  description = "The name of the S3 bucket hosting the frontend"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.blend_user_pool.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.blend_client.id
}

output "cognito_domain" {
  value = "https://${aws_cognito_user_pool_domain.blend_domain.domain}.auth.us-east-1.amazoncognito.com"
}