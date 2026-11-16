variable "prefix" {
  description = "Name prefix."
  type        = string
}

variable "source_dir" {
  description = "Folder holding the Lambda code (app/api)."
  type        = string
}

variable "kms_key_arn" {
  description = "Customer-managed key that encrypts the tables."
  type        = string
}

variable "table_names" {
  description = "Map of logical table name to table name."
  type        = map(string)
}

variable "table_arns" {
  description = "Map of logical table name to table ARN."
  type        = map(string)
}

variable "guardrail_id" {
  description = "Bedrock guardrail ID. Empty disables the guard gateway's call to Bedrock (it then fails closed)."
  type        = string
  default     = ""
}

variable "guardrail_arn" {
  description = "Bedrock guardrail ARN."
  type        = string
  default     = ""
}

variable "guardrail_version" {
  description = "Published guardrail version."
  type        = string
  default     = ""
}

variable "cxone_egress_cidrs" {
  description = "Public IP ranges CXone calls from."
  type        = list(string)
  default     = []
}

variable "extra_allowed_cidrs" {
  description = "Extra ranges allowed to call the API (your own IP while testing)."
  type        = list(string)
  default     = []
}

variable "enable_waf" {
  description = "Attach a web application firewall."
  type        = bool
  default     = true
}

variable "api_stage_name" {
  description = "API Gateway stage name."
  type        = string
  default     = "v1"
}

variable "api_rate_limit_per_5min" {
  description = "WAF rate limit per source IP per five minutes."
  type        = number
  default     = 2000
}

variable "api_throttle_rate" {
  description = "Steady requests per second."
  type        = number
  default     = 50
}

variable "api_throttle_burst" {
  description = "Burst requests."
  type        = number
  default     = 100
}

variable "log_retention_days" {
  description = "Lambda log retention."
  type        = number
  default     = 30
}

variable "bedrock_model_id" {
  description = "Model or inference profile ID for the grounded answer function. Empty turns the answer function off (it then says so and sends the caller to a person)."
  type        = string
  default     = ""
}
