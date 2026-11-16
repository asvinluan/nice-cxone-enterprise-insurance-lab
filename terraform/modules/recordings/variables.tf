variable "prefix" {
  description = "Name prefix."
  type        = string
}

variable "kms_key_arn" {
  description = "Key used to encrypt the bucket."
  type        = string
}

variable "force_destroy" {
  description = "Allow destroy to empty the bucket. Lab only."
  type        = bool
  default     = true
}

variable "enable_object_lock" {
  description = "Create the bucket with Object Lock."
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "GOVERNANCE or COMPLIANCE."
  type        = string
  default     = "GOVERNANCE"
}

variable "retention_days" {
  description = "Days before an object expires (and the Object Lock default retention)."
  type        = number
  default     = 90
}

variable "transition_days" {
  description = "Days before objects move to a cheaper class. Must be less than retention_days."
  type        = number
  default     = 30
}
