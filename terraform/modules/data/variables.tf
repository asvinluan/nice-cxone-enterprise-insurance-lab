variable "prefix" {
  description = "Name prefix."
  type        = string
}

variable "kms_key_arn" {
  description = "Key used to encrypt the tables."
  type        = string
}

variable "deletion_protection" {
  description = "Protect the tables from deletion."
  type        = bool
  default     = false
}
