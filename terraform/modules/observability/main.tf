############################################################################
# Observability: alarms that someone will act on, built from two sources.
#   1. AWS service metrics (Lambda errors, throttles, p99 duration, API 5XX, WAF blocks).
#   2. Metrics made from the functions' own one-line JSON logs (guardrail
#      blocks and errors, lock-outs). The logs carry no customer identifiers.
############################################################################
locals {
  upper     = upper(var.prefix)
  namespace = "${local.upper}/CXone"
  actions   = [var.alarm_topic_arn]
}

# ---------------------------------------------------------- service metrics

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.function_names

  alarm_name          = "${each.value}-Errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = var.function_names

  alarm_name          = "${each.value}-Throttles"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = each.value }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
}

# p99, not the average. If 99 calls take 200 ms and one takes 9 seconds the
# average looks healthy, and one caller heard silence. Studio's REST API action
# gives up after 10 seconds by default, so alarm at 5 for warning.
resource "aws_cloudwatch_metric_alarm" "lambda_duration_p99" {
  for_each = var.function_names

  alarm_name          = "${each.value}-DurationP99"
  namespace           = "AWS/Lambda"
  metric_name         = "Duration"
  dimensions          = { FunctionName = each.value }
  extended_statistic  = "p99"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${local.upper}-CXone-API-5XX"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5XXError"
  dimensions          = { ApiName = var.api_name, Stage = var.api_stage_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
}

# A burst of blocked requests is normal internet noise; a sustained, large one
# is worth a look. The threshold is deliberately high.
resource "aws_cloudwatch_metric_alarm" "waf_blocked" {
  count = var.waf_acl_name == "" ? 0 : 1

  alarm_name          = "${local.upper}-CXone-API-WAF-Blocked"
  namespace           = "AWS/WAFV2"
  metric_name         = "BlockedRequests"
  dimensions          = { WebACL = var.waf_acl_name, Rule = "ALL", Region = var.region }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 500
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions
}

# ----------------------------------------------------- metrics from the logs

resource "aws_cloudwatch_log_metric_filter" "guard_blocked" {
  name           = "${var.prefix}-guard-blocked"
  log_group_name = var.log_group_names["guard_gateway"]
  pattern        = "{ $.event = \"guard\" && $.action = \"block\" }"

  metric_transformation {
    namespace = local.namespace
    name      = "GuardBlocked"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "guard_errors" {
  name           = "${var.prefix}-guard-errors"
  log_group_name = var.log_group_names["guard_gateway"]
  pattern        = "{ $.event = \"guard\" && $.result = \"error\" }"

  metric_transformation {
    namespace = local.namespace
    name      = "GuardErrors"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "guard_latency" {
  name           = "${var.prefix}-guard-latency"
  log_group_name = var.log_group_names["guard_gateway"]
  pattern        = "{ $.event = \"guard\" && $.latency_ms = * }"

  metric_transformation {
    namespace = local.namespace
    name      = "GuardLatencyMs"
    value     = "$.latency_ms"
    unit      = "Milliseconds"
  }
}

resource "aws_cloudwatch_log_metric_filter" "policy_locked" {
  name           = "${var.prefix}-policy-locked"
  log_group_name = var.log_group_names["policy_verify"]
  pattern        = "{ $.event = \"policy_verify\" && $.result = \"locked\" }"

  metric_transformation {
    namespace = local.namespace
    name      = "PolicyLockouts"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "claim_locked" {
  name           = "${var.prefix}-claim-locked"
  log_group_name = var.log_group_names["claim_status"]
  pattern        = "{ $.event = \"claim_status\" && $.result = \"locked\" }"

  metric_transformation {
    namespace = local.namespace
    name      = "ClaimLockouts"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "guard_blocked_spike" {
  alarm_name          = "${local.upper}-guard-blocked-spike"
  alarm_description   = "Five or more answers or questions were blocked by the guardrail in five minutes. Either an attack is under way or the guardrail is too strict."
  namespace           = local.namespace
  metric_name         = "GuardBlocked"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions

  depends_on = [aws_cloudwatch_log_metric_filter.guard_blocked]
}

resource "aws_cloudwatch_metric_alarm" "guard_errors" {
  alarm_name          = "${local.upper}-guard-errors"
  alarm_description   = "The guard gateway could not reach the guardrail. It fails closed, so callers are being sent to a person."
  namespace           = local.namespace
  metric_name         = "GuardErrors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions

  depends_on = [aws_cloudwatch_log_metric_filter.guard_errors]
}

resource "aws_cloudwatch_metric_alarm" "lockouts" {
  alarm_name          = "${local.upper}-verification-lockouts"
  alarm_description   = "Several policy lookups were locked out in five minutes. Someone may be guessing policy numbers."
  namespace           = local.namespace
  metric_name         = "PolicyLockouts"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.actions

  depends_on = [aws_cloudwatch_log_metric_filter.policy_locked]
}

# ------------------------------------------------------------------ dashboard

resource "aws_cloudwatch_dashboard" "this" {
  count = var.enable_dashboard ? 1 : 0

  dashboard_name = "${local.upper}-CXone-Integration"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "API calls and errors"
          region  = var.region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 300
          metrics = [["AWS/ApiGateway", "Count", "ApiName", var.api_name, "Stage", var.api_stage_name], [".", "5XXError", ".", ".", ".", "."], [".", "4XXError", ".", ".", ".", "."]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "API latency (p99, ms)"
          region  = var.region
          view    = "timeSeries"
          stat    = "p99"
          period  = 300
          metrics = [["AWS/ApiGateway", "Latency", "ApiName", var.api_name, "Stage", var.api_stage_name]]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Guardrail: blocked and errors"
          region  = var.region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 300
          metrics = [[local.namespace, "GuardBlocked"], [".", "GuardErrors"]]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Verification lock-outs"
          region  = var.region
          view    = "timeSeries"
          stat    = "Sum"
          period  = 300
          metrics = [[local.namespace, "PolicyLockouts"], [".", "ClaimLockouts"]]
        }
      },
    ]
  })
}
