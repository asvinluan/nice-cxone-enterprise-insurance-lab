############################################################################
# Data: five small tables. All on-demand (no capacity to size, no idle cost),
# all encrypted with the customer-managed key, all with point-in-time recovery.
#
#   policies     fictional policies, for the premium and verify lookups
#   claims       fictional claims, for the status lookup
#   cases        the stand-in for a CRM case record
#   attempts     counts failed verifications so a guesser is locked out
#   cat_events   postcodes inside a declared catastrophe (CAT) event
############################################################################
locals {
  tables = {
    policies   = { hash_key = "policy_number", ttl = false }
    claims     = { hash_key = "claim_number", ttl = false }
    cases      = { hash_key = "case_id", ttl = false }
    attempts   = { hash_key = "subject", ttl = true }
    cat_events = { hash_key = "postcode", ttl = false }
  }
}

resource "aws_dynamodb_table" "this" {
  for_each = local.tables

  name                        = "${var.prefix}-${each.key}"
  billing_mode                = "PAY_PER_REQUEST"
  hash_key                    = each.value.hash_key
  deletion_protection_enabled = var.deletion_protection

  attribute {
    name = each.value.hash_key
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  dynamic "ttl" {
    for_each = each.value.ttl ? [1] : []
    content {
      attribute_name = "expires_at"
      enabled        = true
    }
  }
}
