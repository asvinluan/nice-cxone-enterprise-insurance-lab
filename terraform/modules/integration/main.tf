############################################################################
# Integration layer: the small, boring API that CXone Studio scripts call.
#
#   CXone Studio "REST API" action  ->  API Gateway  ->  Lambda  ->  DynamoDB / Bedrock
#
# Why it exists: Studio's REST API action has a 10-second default timeout
# (90 maximum), reads JSON only, accepts about 32 KB of response, retries
# twice by itself and trips a circuit breaker when many calls fail. So every
# function here answers fast, returns a small flat JSON object, is safe to
# retry, and never makes the caller wait in silence.
############################################################################
locals {
  upper = upper(var.prefix)

  # tables: tables the function reads. write: whether it may also write.
  functions = {
    policy_verify = { handler = "handlers.policy_verify", timeout = 8, tables = ["policies", "attempts"], write = true, bedrock = false, model = false }
    claim_status  = { handler = "handlers.claim_status", timeout = 8, tables = ["claims", "attempts"], write = true, bedrock = false, model = false }
    crm_case      = { handler = "handlers.crm_case", timeout = 8, tables = ["cases"], write = true, bedrock = false, model = false }
    cat_check     = { handler = "handlers.cat_check", timeout = 5, tables = ["cat_events"], write = false, bedrock = false, model = false }
    guard_gateway = { handler = "handlers.guard_gateway", timeout = 8, tables = [], write = false, bedrock = true, model = false }
    ai_answer     = { handler = "handlers.ai_answer", timeout = 8, tables = [], write = false, bedrock = true, model = true }
    health        = { handler = "handlers.health", timeout = 5, tables = ["policies"], write = false, bedrock = false, model = false }
  }

  # path = parent group (empty = directly under /v1) and the last path part.
  routes = {
    policy_verify = { parent = "policy", part = "verify", method = "POST", fn = "policy_verify" }
    claim_status  = { parent = "claims", part = "status", method = "POST", fn = "claim_status" }
    crm_case      = { parent = "crm", part = "cases", method = "POST", fn = "crm_case" }
    cat_check     = { parent = "cat", part = "check", method = "POST", fn = "cat_check" }
    guard         = { parent = "", part = "guard", method = "POST", fn = "guard_gateway" }
    ai_answer     = { parent = "ai", part = "answer", method = "POST", fn = "ai_answer" }
    health        = { parent = "", part = "health", method = "GET", fn = "health" }
  }

  groups = toset(["policy", "claims", "crm", "cat", "ai"])

  table_env = { for k, v in var.table_names : "TABLE_${upper(k)}" => v }

  # "apac.amazon.nova-lite-v1:0" is an inference profile; the model behind it is the same
  # string without the "apac." prefix.
  foundation_model_id = replace(var.bedrock_model_id, "/^[a-z]+\\./", "")
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "archive_file" "api" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.build/api.zip"
  excludes    = ["__pycache__", "tests"]
}

# ---------------------------------------------------------------- logs, roles

resource "aws_cloudwatch_log_group" "fn" {
  for_each          = local.functions
  name              = "/aws/lambda/${local.upper}-${each.key}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# One role per function: the guard gateway can call Bedrock and cannot read a
# table; the policy lookup can read policies and cannot call Bedrock.
data "aws_iam_policy_document" "fn" {
  for_each = local.functions

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.fn[each.key].arn}:*"]
  }

  dynamic "statement" {
    for_each = length(each.value.tables) > 0 ? [1] : []
    content {
      sid       = "Tables"
      actions   = each.value.write ? ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem"] : ["dynamodb:GetItem"]
      resources = [for t in each.value.tables : var.table_arns[t]]
    }
  }

  dynamic "statement" {
    for_each = length(each.value.tables) > 0 ? [1] : []
    content {
      sid       = "TableKey"
      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = [var.kms_key_arn]
    }
  }

  dynamic "statement" {
    for_each = each.value.bedrock && var.guardrail_arn != "" ? [1] : []
    content {
      sid       = "ApplyOneGuardrail"
      actions   = ["bedrock:ApplyGuardrail"]
      resources = [var.guardrail_arn]
    }
  }

  # One model, through one inference profile. The foundation-model ARN has a wildcard
  # region because a cross-region profile may run the request elsewhere in its geography.
  dynamic "statement" {
    for_each = each.value.model && var.bedrock_model_id != "" ? [1] : []
    content {
      sid     = "InvokeOneModel"
      actions = ["bedrock:InvokeModel"]
      resources = [
        "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.bedrock_model_id}",
        "arn:aws:bedrock:*::foundation-model/${local.foundation_model_id}",
      ]
    }
  }
}

resource "aws_iam_role" "fn" {
  for_each           = local.functions
  name               = "${local.upper}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy" "fn" {
  for_each = local.functions
  name     = "${var.prefix}-${each.key}"
  role     = aws_iam_role.fn[each.key].id
  policy   = data.aws_iam_policy_document.fn[each.key].json
}

# ----------------------------------------------------------------- functions

resource "aws_lambda_function" "fn" {
  for_each = local.functions

  function_name = "${local.upper}-${each.key}"
  role          = aws_iam_role.fn[each.key].arn
  runtime       = "python3.12"
  architectures = ["arm64"]
  handler       = each.value.handler
  timeout       = each.value.timeout
  memory_size   = 256

  filename         = data.archive_file.api.output_path
  source_code_hash = data.archive_file.api.output_base64sha256

  environment {
    variables = merge(local.table_env, {
      MODEL_ID          = var.bedrock_model_id
      GUARDRAIL_ID      = var.guardrail_id
      GUARDRAIL_VERSION = var.guardrail_version
      REQUIRE_GUARDRAIL = var.guardrail_id != "" ? "true" : "false"
      SERVICE_VERSION   = "1.0.0"
    })
  }

  depends_on = [aws_cloudwatch_log_group.fn, aws_iam_role_policy.fn]
}

# ------------------------------------------------------------------ the API

resource "aws_api_gateway_rest_api" "this" {
  name = "${local.upper}-CXone-Integration-API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "v1" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "v1"
}

resource "aws_api_gateway_resource" "group" {
  for_each    = local.groups
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = each.key
}

locals {
  parent_ids = merge(
    { "" = aws_api_gateway_resource.v1.id },
    { for k, r in aws_api_gateway_resource.group : k => r.id },
  )
}

resource "aws_api_gateway_resource" "leaf" {
  for_each    = local.routes
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = local.parent_ids[each.value.parent]
  path_part   = each.value.part
}

resource "aws_api_gateway_method" "leaf" {
  for_each = local.routes

  rest_api_id      = aws_api_gateway_rest_api.this.id
  resource_id      = aws_api_gateway_resource.leaf[each.key].id
  http_method      = each.value.method
  authorization    = "NONE" # the API key and the IP allow-list in WAF are the gates; see the Build Manual, Part 12
  api_key_required = true
}

resource "aws_api_gateway_integration" "leaf" {
  for_each = local.routes

  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.leaf[each.key].id
  http_method             = aws_api_gateway_method.leaf[each.key].http_method
  integration_http_method = "POST" # API Gateway always calls Lambda with POST
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.fn[each.value.fn].invoke_arn
}

resource "aws_lambda_permission" "apigw" {
  for_each = local.routes

  statement_id  = "AllowApiGateway-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn[each.value.fn].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/${each.value.method}/v1/${join("/", compact([each.value.parent, each.value.part]))}"
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  # Redeploy whenever the API definition changes. Editing without deploying is
  # the API Gateway version of "I changed the script and forgot to publish".
  triggers = {
    redeployment = sha1(jsonencode([
      [for r in aws_api_gateway_resource.leaf : r.id],
      [for m in aws_api_gateway_method.leaf : m.id],
      [for i in aws_api_gateway_integration.leaf : i.id],
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.api_stage_name
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    throttling_burst_limit = var.api_throttle_burst
    throttling_rate_limit  = var.api_throttle_rate
  }
}

# --------------------------------------------------------------- API key and plan

resource "aws_api_gateway_api_key" "cxone" {
  name    = "${var.prefix}-cxone-studio"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "cxone" {
  name = "${var.prefix}-cxone-studio"

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }

  throttle_settings {
    rate_limit  = var.api_throttle_rate
    burst_limit = var.api_throttle_burst
  }

  quota_settings {
    limit  = 200000
    period = "DAY"
  }
}

resource "aws_api_gateway_usage_plan_key" "cxone" {
  key_id        = aws_api_gateway_api_key.cxone.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.cxone.id
}

# ------------------------------------------------------------------------ WAF
# WAF sits in front of API Gateway. Default action is BLOCK: only the listed
# CXone egress ranges (and any extra ranges you add while testing) get through.
# An empty list blocks everyone, which is the safe failure.

resource "aws_wafv2_ip_set" "allowed" {
  count = var.enable_waf ? 1 : 0

  name               = "${var.prefix}-cxone-allowed"
  description        = "CXone egress ranges and test ranges"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = concat(var.cxone_egress_cidrs, var.extra_allowed_cidrs)
}

resource "aws_wafv2_web_acl" "this" {
  count = var.enable_waf ? 1 : 0

  name        = "${local.upper}-CXone-API-ACL"
  description = "Default block; allow CXone and test ranges; rate limit; managed rules"
  scope       = "REGIONAL"

  default_action {
    block {}
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = var.api_rate_limit_per_5min
        aggregate_key_type    = "IP"
        evaluation_window_sec = 300
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AllowCxoneAndTestRanges"
    priority = 4

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.allowed[0].arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AllowCxoneAndTestRanges"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.upper}-CXone-API-ACL"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "api" {
  count = var.enable_waf ? 1 : 0

  resource_arn = aws_api_gateway_stage.this.arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}
