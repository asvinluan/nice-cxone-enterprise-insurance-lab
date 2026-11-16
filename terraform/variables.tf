variable "region" {
  description = "Primary AWS region. Sydney keeps customer data in Australia."
  type        = string
  default     = "ap-southeast-2"
}

variable "dr_region" {
  description = "Disaster-recovery region. Melbourne keeps the copy in Australia."
  type        = string
  default     = "ap-southeast-4"
}

variable "prefix" {
  description = "Short lower-case prefix for every name (letters, digits, hyphen)."
  type        = string
  default     = "ki"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.prefix))
    error_message = "Use 2 to 12 characters: lower-case letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment label: lab, nonprod or prod. The lab default is cheap and easy to delete."
  type        = string
  default     = "lab"

  validation {
    condition     = contains(["lab", "nonprod", "prod"], var.environment)
    error_message = "environment must be lab, nonprod or prod."
  }
}

variable "tags" {
  description = "Extra tags added to everything."
  type        = map(string)
  default     = {}
}

# ----------------------------------------------------------------- who may call the API

variable "cxone_egress_cidrs" {
  description = "Public IP ranges CXone calls from. Get them from NICE or your carrier and paste them here. Empty means nobody can call the API (a safe default)."
  type        = list(string)
  default     = []
}

variable "extra_allowed_cidrs" {
  description = "Extra ranges allowed to call the API, for example your own public IP as x.x.x.x/32 while testing. Remove after testing."
  type        = list(string)
  default     = []
}

# ----------------------------------------------------------------- switches (cost and risk)

variable "enable_waf" {
  description = "Put a web application firewall in front of the API. About 10 USD a month with the rules used here. Leave on for anything beyond a quick test."
  type        = bool
  default     = true
}

variable "enable_guardrail" {
  description = "Create the Bedrock guardrail and let the guard gateway use it."
  type        = bool
  default     = true
}

variable "enable_object_lock" {
  description = "Create the archive bucket with S3 Object Lock (write once, read many). It can only be set when the bucket is created, and locked objects cannot be deleted until retention ends. Keep false in a throwaway lab."
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "GOVERNANCE (some users may override) or COMPLIANCE (nobody can override, not even root)."
  type        = string
  default     = "GOVERNANCE"

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "object_lock_mode must be GOVERNANCE or COMPLIANCE."
  }
}

variable "enable_dr_replication" {
  description = "Copy the archive bucket to the DR region. Needs versioning (on) and doubles storage cost."
  type        = bool
  default     = false
}

variable "enable_dashboard" {
  description = "Create a CloudWatch dashboard for the integration layer."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Protect the DynamoDB tables from deletion. Turn on for nonprod and prod; the lab leaves it off so destroy works."
  type        = bool
  default     = false
}

variable "force_destroy_buckets" {
  description = "Allow destroy to empty and delete the archive bucket. Lab only. Has no effect on objects under Object Lock."
  type        = bool
  default     = true
}

# ----------------------------------------------------------------- numbers you will tune

variable "recording_retention_days" {
  description = "Days an archived object is kept before it expires. The lab default is short. A real insurer sets this from its records-retention policy (often several years)."
  type        = number
  default     = 90
}

variable "archive_transition_days" {
  description = "Days before archived objects move to a cheaper storage class. Must be less than the retention."
  type        = number
  default     = 30
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
  description = "Steady requests per second the API accepts."
  type        = number
  default     = 50
}

variable "api_throttle_burst" {
  description = "Burst requests the API accepts."
  type        = number
  default     = 100
}

variable "log_retention_days" {
  description = "How long Lambda logs are kept. Logs hold no customer identifiers."
  type        = number
  default     = 30
}

variable "alarm_email" {
  description = "Email address for alarms. Empty means no email subscription (you will not be told)."
  type        = string
  default     = ""
}

variable "bedrock_model_id" {
  description = "Model or inference profile ID for the grounded GenAI answer (for example apac.amazon.nova-lite-v1:0). Empty keeps it off. WARNING: a cross-region profile such as apac. may process requests outside Australia; check data residency before use."
  type        = string
  default     = ""
}
