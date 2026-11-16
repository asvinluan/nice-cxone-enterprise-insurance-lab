############################################################################
# Optional DR copy of the archive bucket in a second Australian region.
# Versioning is required on both sides. The DR copy has its own key, created in
# the DR region (a key cannot be shared across regions).
############################################################################
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "dr" {
  provider                = aws.dr
  description             = "${var.prefix} CXone archive DR copy"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_s3_bucket" "dr" {
  provider      = aws.dr
  bucket        = "${var.prefix}-cxone-archive-dr-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.dr.arn
    }
  }
}

resource "aws_s3_bucket_versioning" "dr" {
  provider = aws.dr
  bucket   = aws_s3_bucket.dr.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "replicate" {
  statement {
    sid       = "ReadSourceConfig"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [var.source_bucket_arn]
  }

  statement {
    sid       = "ReadSourceObjects"
    actions   = ["s3:GetObjectVersionForReplication", "s3:GetObjectVersionAcl", "s3:GetObjectVersionTagging"]
    resources = ["${var.source_bucket_arn}/*"]
  }

  statement {
    sid       = "WriteDestination"
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = ["${aws_s3_bucket.dr.arn}/*"]
  }

  statement {
    sid       = "DecryptSource"
    actions   = ["kms:Decrypt"]
    resources = [var.source_kms_key_arn]
  }

  statement {
    sid       = "EncryptDestination"
    actions   = ["kms:Encrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.dr.arn]
  }
}

resource "aws_iam_role" "replicate" {
  name               = "${upper(var.prefix)}-archive-replication"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy" "replicate" {
  name   = "${var.prefix}-archive-replication"
  role   = aws_iam_role.replicate.id
  policy = data.aws_iam_policy_document.replicate.json
}

resource "aws_s3_bucket_replication_configuration" "this" {
  bucket = var.source_bucket_id
  role   = aws_iam_role.replicate.arn

  rule {
    id     = "archive-to-dr"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Disabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    destination {
      bucket        = aws_s3_bucket.dr.arn
      storage_class = "STANDARD_IA"

      encryption_configuration {
        replica_kms_key_id = aws_kms_key.dr.arn
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.dr, aws_iam_role_policy.replicate]
}
