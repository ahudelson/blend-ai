variable "region" {
  description = "AWS region for deployment"
  default     = "us-east-1"
}

variable "grok_api_key" {
  description = "API key for Grok (xAI)"
  sensitive   = true
}

variable "openai_api_key" {
  description = "API key for OpenAI"
  sensitive   = true
}

variable "domain_name" {
  description = "Custom domain for CloudFront frontend (e.g., blend.example.com)"
  type        = string
}

variable "root_domain" {
  description = "Root domain of the Route53 Hosted Zone (e.g., example.com)"
  type        = string
}

variable "api_domain_name" {
  description = "Custom domain for API Gateway (e.g., api.example.com)"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID for Deployments"
  type        = string
}

variable "aws_cli_profile" {
  description = "AWS CLI Profile for Deployments"
  type        = string
}