variable "prefix" {
  description = "Name prefix."
  type        = string
}

variable "alarm_email" {
  description = "Email for alarms. Empty means no subscription."
  type        = string
  default     = ""
}
