############################################################################
# Foundation: one customer-managed key and one alarm topic.
#
# One key keeps the lab simple. In production, separate keys for data, the
# archive and logs let you give different teams different access, and let you
# revoke one without touching the others.
############################################################################
resource "aws_kms_key" "this" {
  description             = "${var.prefix} CXone integration layer: tables and archive"
  enable_key_rotation     = true
  deletion_window_in_days = 7 # the minimum. About 1 USD a month while it exists.
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.prefix}-cxone-integration"
  target_key_id = aws_kms_key.this.key_id
}

# An alarm wired to a topic nobody subscribes to is decoration. Set alarm_email,
# or subscribe your paging tool to this topic.
resource "aws_sns_topic" "alarms" {
  name = "${var.prefix}-cxone-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
