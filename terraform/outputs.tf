output "api_url" {
  description = "Base URL for the CXone REST API action, including the stage. Put this in CXone Studio."
  value       = module.integration.api_url
}

output "api_key_id" {
  description = "ID of the API key. The value is sensitive; see api_key_value."
  value       = module.integration.api_key_id
}

output "api_key_value" {
  description = "The API key. Read it with: tofu output -raw api_key_value  . Never commit it."
  value       = module.integration.api_key_value
  sensitive   = true
}

output "table_names" {
  description = "DynamoDB tables."
  value       = module.data.table_names
}

output "archive_bucket" {
  description = "Archive bucket name."
  value       = module.recordings.bucket_id
}

output "guardrail_id" {
  description = "Guardrail ID, or empty if the guardrail is off."
  value       = var.enable_guardrail ? module.guardrail[0].guardrail_id : ""
}

output "guardrail_version" {
  description = "Guardrail version the guard gateway is pinned to."
  value       = var.enable_guardrail ? module.guardrail[0].guardrail_version : ""
}

output "function_names" {
  description = "Lambda function names."
  value       = module.integration.function_names
}

output "dr_bucket" {
  description = "DR archive bucket, or empty if DR replication is off."
  value       = var.enable_dr_replication ? module.dr_replication[0].dr_bucket_id : ""
}

output "alarm_count" {
  description = "How many alarms the observability module created (not counting the WAF alarm)."
  value       = length(module.observability.alarm_names)
}
