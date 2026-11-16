output "guardrail_id" {
  description = "Guardrail ID."
  value       = aws_bedrock_guardrail.this.guardrail_id
}

output "guardrail_arn" {
  description = "Guardrail ARN."
  value       = aws_bedrock_guardrail.this.guardrail_arn
}

output "guardrail_version" {
  description = "Published guardrail version the Lambda is pinned to."
  value       = aws_bedrock_guardrail_version.this.version
}
