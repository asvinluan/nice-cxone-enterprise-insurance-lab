output "alarm_names" {
  description = "Names of the alarms this module created that do not depend on a count."
  value = concat(
    [for a in aws_cloudwatch_metric_alarm.lambda_errors : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.lambda_throttles : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.lambda_duration_p99 : a.alarm_name],
    [aws_cloudwatch_metric_alarm.api_5xx.alarm_name, aws_cloudwatch_metric_alarm.guard_blocked_spike.alarm_name, aws_cloudwatch_metric_alarm.guard_errors.alarm_name, aws_cloudwatch_metric_alarm.lockouts.alarm_name],
  )
}
