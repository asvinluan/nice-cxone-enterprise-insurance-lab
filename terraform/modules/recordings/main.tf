############################################################################
# Archive bucket: the landing zone for exported evidence.
#
# What lands here depends on what the insurer, the carrier and NICE agree: exported call
# recordings or transcripts, configuration snapshots, test evidence. The lab
# proves the CONTROLS of the landing zone, not the export mechanism.
############################################################################
data "aws_caller_identity" "current" {}

locals {
  bucket_name   = "${var.prefix}-cxone-archive-${data.aws_caller_identity.current.account_id}"
  transition_ok = var.transition_days < var.retention_days
}

resource "aws_s3_bucket" "archive" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  # Object Lock can ONLY be switched on when the bucket is created.
  # It is an architecture decision, not an operations one.
  object_lock_enabled = var.enable_object_lock
}

resource "aws_s3_bucket_ownership_controls" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "archive" {
  bucket = aws_s3_bucket.archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_versioning" "archive" {
  bucket = aws_s3_bucket.archive.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.archive.arn,
      "${aws_s3_bucket.archive.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "archive" {
  bucket = aws_s3_bucket.archive.id
  policy = data.aws_iam_policy_document.tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.archive]
}

resource "aws_s3_bucket_object_lock_configuration" "archive" {
  count  = var.enable_object_lock ? 1 : 0
  bucket = aws_s3_bucket.archive.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.archive]
}

resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  bucket = aws_s3_bucket.archive.id

  # By default S3 does not transition objects under 128 KB, and short call
  # recordings are often smaller. Set this explicitly or nothing archives.
  transition_default_minimum_object_size = "varies_by_storage_class"

  rule {
    id     = "archive-then-expire"
    status = "Enabled"

    filter {}

    dynamic "transition" {
      for_each = local.transition_ok ? [1] : []
      content {
        days          = var.transition_days
        storage_class = "GLACIER_IR"
      }
    }

    expiration {
      days = var.retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.archive]
}
