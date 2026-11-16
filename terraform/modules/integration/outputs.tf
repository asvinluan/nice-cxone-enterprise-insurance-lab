output "api_url" {
  description = "Base URL of the integration API, including the stage."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "api_name" {
  description = "API Gateway name (for alarms)."
  value       = aws_api_gateway_rest_api.this.name
}

output "api_stage_name" {
  description = "API Gateway stage name (for alarms)."
  value       = aws_api_gateway_stage.this.stage_name
}

output "api_key_id" {
  description = "ID of the API key. Fetch the value with the AWS CLI; it is not printed here."
  value       = aws_api_gateway_api_key.cxone.id
}

output "api_key_value" {
  description = "The API key value that goes in the CXone REST API action header. Sensitive."
  value       = aws_api_gateway_api_key.cxone.value
  sensitive   = true
}

output "function_names" {
  description = "Map of logical function name to Lambda function name."
  value       = { for k, f in aws_lambda_function.fn : k => f.function_name }
}

output "log_group_names" {
  description = "Map of logical function name to log group name."
  value       = { for k, g in aws_cloudwatch_log_group.fn : k => g.name }
}

output "waf_acl_name" {
  description = "Name of the web ACL, or empty if WAF is off."
  value       = var.enable_waf ? aws_wafv2_web_acl.this[0].name : ""
}
