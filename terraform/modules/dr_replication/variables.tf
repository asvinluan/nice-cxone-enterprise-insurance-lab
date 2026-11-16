variable "prefix" {
  description = "Name prefix."
  type        = string
}

variable "source_bucket_id" {
  description = "Primary archive bucket name."
  type        = string
}

variable "source_bucket_arn" {
  description = "Primary archive bucket ARN."
  type        = string
}

variable "source_kms_key_arn" {
  description = "Key that encrypts the primary bucket."
  type        = string
}

variable "force_destroy" {
  description = "Allow destroy to empty the DR bucket. Lab only."
  type        = bool
  default     = true
}
