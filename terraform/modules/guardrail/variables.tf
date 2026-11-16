variable "prefix" {
  description = "Name prefix."
  type        = string
}

variable "blocked_message" {
  description = "What the caller hears or reads when the guardrail blocks something."
  type        = string
  default     = "Sorry, I can't help with that here. I can connect you to a person."
}
