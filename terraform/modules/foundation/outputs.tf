output "kms_key_arn" {
  description = "ARN of the customer-managed key."
  value       = aws_kms_key.this.arn
}

output "alarm_topic_arn" {
  description = "ARN of the alarm topic."
  value       = aws_sns_topic.alarms.arn
}
