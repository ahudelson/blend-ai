# Backend Lambda - Docker Image
resource "aws_lambda_function" "blend_api" {
  function_name = "blend-api"
  role          = aws_iam_role.lambda_role.arn
  package_type  = "Image"
  image_uri     = "${var.aws_account_id}.dkr.ecr.us-east-1.amazonaws.com/blend-api:latest"
  timeout       = 900
  memory_size   = 10240
  architectures = ["arm64"]
  environment {
    variables = {
      GROK_API_KEY   = var.grok_api_key
      OPENAI_API_KEY = var.openai_api_key
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "blend-ai-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

# Cognito User Pool
resource "aws_cognito_user_pool" "blend_user_pool" {
  name = "blend-user-pool"
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OFF"
}

resource "aws_cognito_user_pool_client" "blend_client" {
  name                                 = "blend-app-client"
  user_pool_id                         = aws_cognito_user_pool.blend_user_pool.id
  generate_secret                      = false
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]
  allowed_oauth_flows_user_pool_client = true
  callback_urls                        = ["https://${var.domain_name}/callback"]
  logout_urls                          = ["https://${var.domain_name}/logout"]
  supported_identity_providers         = ["COGNITO"]
}

resource "aws_cognito_user_pool_domain" "blend_domain" {
  domain       = "blend-auth-${random_string.suffix.result}"
  user_pool_id = aws_cognito_user_pool.blend_user_pool.id
}

# API Gateway
resource "aws_api_gateway_rest_api" "blend_api" {
  name = "BlendAPI"
}

resource "aws_api_gateway_resource" "blend_resource" {
  rest_api_id = aws_api_gateway_rest_api.blend_api.id
  parent_id   = aws_api_gateway_rest_api.blend_api.root_resource_id
  path_part   = "blend"
}

resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name                   = "cognito-authorizer"
  rest_api_id            = aws_api_gateway_rest_api.blend_api.id
  type                   = "COGNITO_USER_POOLS"
  provider_arns          = [aws_cognito_user_pool.blend_user_pool.arn]
  identity_source        = "method.request.header.Authorization"
}

resource "aws_api_gateway_method" "blend_method" {
  rest_api_id   = aws_api_gateway_rest_api.blend_api.id
  resource_id   = aws_api_gateway_resource.blend_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "blend_integration" {
  rest_api_id             = aws_api_gateway_rest_api.blend_api.id
  resource_id             = aws_api_gateway_resource.blend_resource.id
  http_method             = aws_api_gateway_method.blend_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.blend_api.invoke_arn
}

resource "aws_api_gateway_method" "blend_options_method" {
  rest_api_id   = aws_api_gateway_rest_api.blend_api.id
  resource_id   = aws_api_gateway_resource.blend_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "blend_options_integration" {
  rest_api_id             = aws_api_gateway_rest_api.blend_api.id
  resource_id             = aws_api_gateway_resource.blend_resource.id
  http_method             = aws_api_gateway_method.blend_options_method.http_method
  type                    = "MOCK"
  request_templates       = { "application/json" = "{\"statusCode\": 200}" }
}

resource "aws_api_gateway_method_response" "blend_options_response" {
  rest_api_id = aws_api_gateway_rest_api.blend_api.id
  resource_id = aws_api_gateway_resource.blend_resource.id
  http_method = aws_api_gateway_method.blend_options_method.http_method
  status_code = "200"
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "blend_options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.blend_api.id
  resource_id = aws_api_gateway_resource.blend_resource.id
  http_method = aws_api_gateway_method.blend_options_method.http_method
  status_code = aws_api_gateway_method_response.blend_options_response.status_code
  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'https://${var.domain_name}'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Authorization'"
  }
  depends_on = [aws_api_gateway_integration.blend_options_integration]
}

resource "aws_api_gateway_deployment" "blend_deployment" {
  rest_api_id = aws_api_gateway_rest_api.blend_api.id
  depends_on  = [
    aws_api_gateway_integration.blend_integration,
    aws_api_gateway_integration.blend_options_integration,
    aws_api_gateway_integration_response.blend_options_integration_response
  ]
}

resource "aws_api_gateway_stage" "prod" {
  rest_api_id   = aws_api_gateway_rest_api.blend_api.id
  deployment_id = aws_api_gateway_deployment.blend_deployment.id
  stage_name    = "prod"
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_logs.arn
    format          = "$context.requestId $context.identity.sourceIp $context.requestTime $context.httpMethod $context.path $context.status $context.error.message"
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_logs" {
  name              = "/aws/apigateway/blend-api"
  retention_in_days = 7
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.blend_api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  method_path = "*/*"
  settings {
    logging_level      = "INFO"
    data_trace_enabled = true
    metrics_enabled    = true
  }
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.blend_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.blend_api.execution_arn}/*/*"
}

# API Gateway Custom Domain
resource "aws_api_gateway_domain_name" "blend_api_domain" {
  domain_name              = "${var.api_domain_name}"
  regional_certificate_arn = aws_acm_certificate.api_cert.arn
  endpoint_configuration {
    types = ["REGIONAL"]
  }
  depends_on = [aws_acm_certificate_validation.api_cert]
}

resource "aws_api_gateway_base_path_mapping" "blend_mapping" {
  api_id      = aws_api_gateway_rest_api.blend_api.id
  stage_name  = aws_api_gateway_stage.prod.stage_name
  domain_name = aws_api_gateway_domain_name.blend_api_domain.domain_name
  base_path   = ""
}

# ACM Certificate for API Gateway
resource "aws_acm_certificate" "api_cert" {
  provider          = aws.acm
  domain_name       = "${var.api_domain_name}"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "api_cert" {
  provider                = aws.acm
  certificate_arn         = aws_acm_certificate.api_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.api_cert_validation : record.fqdn]
}

# Route53 Record for API Gateway
resource "aws_route53_record" "api" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "${var.api_domain_name}"
  type    = "A"
  alias {
    name                   = aws_api_gateway_domain_name.blend_api_domain.regional_domain_name
    zone_id                = aws_api_gateway_domain_name.blend_api_domain.regional_zone_id
    evaluate_target_health = false
  }
}

# S3 Bucket - Private, accessed via CloudFront OAI
resource "aws_s3_bucket" "frontend" {
  bucket = "blend-ai-frontend-${random_string.suffix.result}"
}

resource "aws_s3_bucket_website_configuration" "frontend_config" {
  bucket = aws_s3_bucket.frontend.id
  index_document { suffix = "index.html" }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# ACM Certificate for CloudFront
resource "aws_acm_certificate" "cert" {
  provider          = aws.acm
  domain_name       = var.domain_name
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.acm
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# Route53 Hosted Zone Data
data "aws_route53_zone" "zone" {
  name         = var.root_domain
  private_zone = false
}

# CloudFront Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${var.domain_name}"
}

# CloudFront Distribution with Custom Domain and ACM Cert
resource "aws_cloudfront_distribution" "frontend_dist" {
  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.frontend.id}"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  price_class         = "PriceClass_100"
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend.id}"
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
    viewer_protocol_policy = "redirect-to-https"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }
  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method  = "sni-only"
  }
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
    error_caching_min_ttl = 0
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
    error_caching_min_ttl = 0
  }
}

# S3 Bucket Policy - Restrict to CloudFront OAI
resource "aws_s3_bucket_policy" "frontend_policy" {
  bucket = aws_s3_bucket.frontend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        AWS = "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${aws_cloudfront_origin_access_identity.oai.id}"
      }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.frontend.arn}/*"
    }]
  })
}

# Route53 Record for CloudFront
resource "aws_route53_record" "frontend" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.frontend_dist.domain_name
    zone_id                = aws_cloudfront_distribution.frontend_dist.hosted_zone_id
    evaluate_target_health = false
  }
}