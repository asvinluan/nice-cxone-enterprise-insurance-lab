variable "prefix" {
  description = "Name prefix."
  type        = string
}

variable "region" {
  description = "AWS region, used in dashboard widgets and WAF metric dimensions."
  type        = string
}

variable "alarm_topic_arn" {
  description = "SNS topic that receives alarms."
  type        = string
}

variable "function_names" {
  description = "Map of logical function name to Lambda function name."
  type        = map(string)
}

variable "log_group_names" {
  description = "Map of logical function name to log group name."
  type        = map(string)
}

variable "api_name" {
  description = "API Gateway name."
  type        = string
}

variable "api_stage_name" {
  description = "API Gateway stage name."
  type        = string
}

variable "waf_acl_name" {
  description = "Web ACL name, or empty if WAF is off."
  type        = string
  default     = ""
}

variable "enable_dashboard" {
  description = "Create the dashboard."
  type        = bool
  default     = true
}
