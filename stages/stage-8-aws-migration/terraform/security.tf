# INTRODUCED: Stage 8 — AWS Migration
# PURPOSE: AWS-native security services — GuardDuty, CloudTrail, VPC Flow Logs
# FRAMEWORK: PCI-DSS 10.2, SOC2 CC7.2, CIS AWS Foundations Benchmark
#
# Estimated lab-scale cost (rough):
# - GuardDuty: ~$1–3/month
# - CloudTrail: ~$2/month (first trail is free; S3 storage costs)
# - VPC Flow Logs: ~$0.50/month
# Total additional cost: ~$4–6/month

locals {
  common_tags = {
    Project     = var.project_name
    Stage       = "8"
    ManagedBy   = "terraform"
    Environment = var.environment
  }
}

# ── KMS: encrypt log data at rest ──────────────────────────────────────────────
# Why: CloudTrail, CloudWatch logs and other sensitive telemetry should be encrypted.
# PCI-DSS 3.6: annual key rotation (AWS-managed rotation).

data "aws_iam_policy_document" "kms_policy" {
  statement {
    sid     = "AllowAccountRoot"
    effect  = "Allow"
    actions = ["kms:*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    resources = ["*"]
  }

  # Allow CloudTrail to use the CMK for log file encryption.
  statement {
    sid    = "AllowCloudTrailService"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # Allow CloudWatch Logs service to use the CMK for encrypted log groups.
  statement {
    sid    = "AllowCloudWatchLogsService"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    resources = ["*"]
  }
}

resource "aws_kms_key" "clearledger" {
  description             = "ClearLedger encryption key for logs and secrets"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.kms_policy.json
  tags   = local.common_tags
}

resource "aws_kms_alias" "clearledger" {
  name          = "alias/clearledger"
  target_key_id = aws_kms_key.clearledger.key_id
}

# ── GuardDuty: account-level threat detection ─────────────────────────────────
# GuardDuty detects threats that Falco cannot:
# - Crypto mining (unusual EC2 CPU patterns)
# - Credential theft (API calls from unusual geographies)
# - S3 exfiltration (unusual data access patterns)
# - Port scanning from within the VPC
# Falco watches inside pods. GuardDuty watches the AWS account.

resource "aws_guardduty_detector" "clearledger" {
  enable = true

  datasources {
    s3_logs { enable = true }
    kubernetes {
      audit_logs { enable = true } # critical: watches EKS API calls
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes { enable = true }
      }
    }
  }

  tags = local.common_tags
}

# ── CloudTrail: every AWS API call ────────────────────────────────────────────
# PCI-DSS 10.7 requires audit log retention for 12 months.
# S3 lifecycle below enforces this automatically (Glacier after 90d, delete after 365d).

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${var.project_name}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "cloudtrail-retention"
    status = "Enabled"
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration {
      days = 365
    }
  }
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  statement {
    sid    = "AllowCloudTrailGetBucketAcl"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${var.project_name}"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.clearledger.arn
  tags              = local.common_tags
}

data "aws_iam_policy_document" "cloudtrail_cloudwatch_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name               = "${var.project_name}-cloudtrail-cloudwatch"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_cloudwatch_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "cloudtrail_cloudwatch_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  name   = "${var.project_name}-cloudtrail-cloudwatch"
  role   = aws_iam_role.cloudtrail_cloudwatch.id
  policy = data.aws_iam_policy_document.cloudtrail_cloudwatch_permissions.json
}

resource "aws_cloudtrail" "clearledger" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  tags = local.common_tags
}

# ── VPC Flow Logs: network forensics ──────────────────────────────────────────
# They capture: source IP, dest IP, port, protocol, bytes, accepted/rejected
# They don't capture: packet payloads (requires a different tool)
# For fintech: required for incident forensics and PCI-DSS 10.6

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${var.project_name}-flow-logs"
  retention_in_days = 90
  tags              = local.common_tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.project_name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "flow_logs_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${var.project_name}-flow-logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_permissions.json
}

resource "aws_flow_log" "clearledger_vpc" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn
  traffic_type    = "ALL" # not just REJECT — ALL is needed for forensics
  vpc_id          = aws_vpc.main.id

  tags = local.common_tags
}

# ── AWS Config: infrastructure compliance evidence ────────────────────────────

resource "aws_s3_bucket" "config" {
  bucket        = "${var.project_name}-config-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "config_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config" {
  name               = "${var.project_name}-config"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRole"
}

resource "aws_config_configuration_recorder" "clearledger" {
  name     = var.project_name
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported = true
  }
}

resource "aws_config_delivery_channel" "clearledger" {
  name           = var.project_name
  s3_bucket_name = aws_s3_bucket.config.id

  depends_on = [aws_config_configuration_recorder.clearledger]
}

resource "aws_config_configuration_recorder_status" "clearledger" {
  name       = aws_config_configuration_recorder.clearledger.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.clearledger]
}

# AWS Config managed rules (CIS AWS Foundations-aligned examples)

resource "aws_config_config_rule" "ec2_imdsv2_check" {
  name = "ec2-imdsv2-check"
  source {
    owner             = "AWS"
    source_identifier = "EC2_IMDSV2_CHECK"
  }
  tags = local.common_tags
}

resource "aws_config_config_rule" "restricted_ssh" {
  name = "restricted-ssh"
  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
  tags = local.common_tags
}

resource "aws_config_config_rule" "s3_public_read_prohibited" {
  name = "s3-bucket-public-read-prohibited"
  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
  tags = local.common_tags
}
