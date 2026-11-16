############################################################################
# The whole supporting layer, wired together.
#
# What this builds: the AWS side of a NICE CXone contact centre: the API CXone
# Studio scripts call, its data, its guardrail, its alarms and an archive bucket.
#
# What this does NOT build: CXone itself. NICE publishes no Terraform provider
# for CXone that I could find, so CXone is configured from the JSON files in
# cxone/config using the scripts in scripts/. See docs/BUILD-MANUAL.md, Part 12.
############################################################################
module "foundation" {
  source = "./modules/foundation"

  prefix      = var.prefix
  alarm_email = var.alarm_email
}

module "data" {
  source = "./modules/data"

  prefix              = var.prefix
  kms_key_arn         = module.foundation.kms_key_arn
  deletion_protection = var.deletion_protection
}

module "recordings" {
  source = "./modules/recordings"

  prefix             = var.prefix
  kms_key_arn        = module.foundation.kms_key_arn
  force_destroy      = var.force_destroy_buckets
  enable_object_lock = var.enable_object_lock
  object_lock_mode   = var.object_lock_mode
  retention_days     = var.recording_retention_days
  transition_days    = var.archive_transition_days
}

module "guardrail" {
  source = "./modules/guardrail"
  count  = var.enable_guardrail ? 1 : 0

  prefix = var.prefix
}

module "integration" {
  source = "./modules/integration"

  prefix                  = var.prefix
  source_dir              = "${path.root}/../app/api"
  kms_key_arn             = module.foundation.kms_key_arn
  table_names             = module.data.table_names
  table_arns              = module.data.table_arns
  guardrail_id            = var.enable_guardrail ? module.guardrail[0].guardrail_id : ""
  guardrail_arn           = var.enable_guardrail ? module.guardrail[0].guardrail_arn : ""
  guardrail_version       = var.enable_guardrail ? module.guardrail[0].guardrail_version : ""
  bedrock_model_id        = var.bedrock_model_id
  cxone_egress_cidrs      = var.cxone_egress_cidrs
  extra_allowed_cidrs     = var.extra_allowed_cidrs
  enable_waf              = var.enable_waf
  api_stage_name          = var.api_stage_name
  api_rate_limit_per_5min = var.api_rate_limit_per_5min
  api_throttle_rate       = var.api_throttle_rate
  api_throttle_burst      = var.api_throttle_burst
  log_retention_days      = var.log_retention_days
}

module "observability" {
  source = "./modules/observability"

  prefix           = var.prefix
  region           = var.region
  alarm_topic_arn  = module.foundation.alarm_topic_arn
  function_names   = module.integration.function_names
  log_group_names  = module.integration.log_group_names
  api_name         = module.integration.api_name
  api_stage_name   = module.integration.api_stage_name
  waf_acl_name     = module.integration.waf_acl_name
  enable_dashboard = var.enable_dashboard
}

module "dr_replication" {
  source = "./modules/dr_replication"
  count  = var.enable_dr_replication ? 1 : 0

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  prefix             = var.prefix
  source_bucket_id   = module.recordings.bucket_id
  source_bucket_arn  = module.recordings.bucket_arn
  source_kms_key_arn = module.foundation.kms_key_arn
  force_destroy      = var.force_destroy_buckets
}
