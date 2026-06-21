# INTRODUCED: Stage 8 — AWS Migration
# PURPOSE: IRSA roles for External Secrets Operator and Falco.
#          These give specific pods the minimum AWS permissions they need
#          without granting permissions to the entire node group.

locals {
  oidc_provider     = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
  oidc_provider_arn = aws_iam_openid_connect_provider.eks.arn
}

# ── External Secrets Operator IRSA ───────────────────────────────────────────
# Why: ESO runs in the cluster and reads from Secrets Manager to create K8s Secrets.
# This role is assumed by the ESO service account via IRSA — not by every node.

data "aws_iam_policy_document" "eso_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      # Why this service account: ESO default service account in its namespace.
      values = ["system:serviceaccount:external-secrets:external-secrets"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eso_permissions" {
  statement {
    sid    = "GetSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    # Why scoped to specific secrets: least privilege — ESO only needs to read
    # ClearLedger secrets, not every secret in the account.
    resources = [
      aws_secretsmanager_secret.postgres.arn,
      aws_secretsmanager_secret.auth_service.arn,
      aws_secretsmanager_secret.ledger_service.arn,
    ]
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.project_name}-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume_role.json

  tags = {
    Name = "${var.project_name}-eso-role"
  }
}

resource "aws_iam_role_policy" "eso_permissions" {
  name   = "${var.project_name}-eso-policy"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_permissions.json
}

# ── Falco IRSA (CloudWatch log export) ───────────────────────────────────────
# Why: Falco can export alerts to CloudWatch Logs for long-term retention
# and integration with AWS security tooling (GuardDuty, Security Hub).
# This role is assumed by the Falco service account via IRSA.

data "aws_iam_policy_document" "falco_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:falco:falco"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "falco_permissions" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/clearledger/falco*",
    ]
  }
}

resource "aws_iam_role" "falco" {
  name               = "${var.project_name}-falco-role"
  assume_role_policy = data.aws_iam_policy_document.falco_assume_role.json

  tags = {
    Name = "${var.project_name}-falco-role"
  }
}

resource "aws_iam_role_policy" "falco_permissions" {
  name   = "${var.project_name}-falco-policy"
  role   = aws_iam_role.falco.id
  policy = data.aws_iam_policy_document.falco_permissions.json
}

# ═══════════════════════════════════════════════════════════════════════════
# ClearLedger workload IRSA — auth / ledger / notification
# Trust: StringEquals on OIDC :sub (never StringLike — no wildcards on SA binding).
# Permissions: fully qualified secret ARNs only; explicit Deny on other ClearLedger secrets.
# Boundary: caps blast radius even if a future policy edit adds broad Allow statements.
# ═══════════════════════════════════════════════════════════════════════════

# Permission boundary (Deny-only): denies ec2/iam/s3/lambda/dynamodb even if a future
# overly broad Allow is attached to the role. Does not grant permissions by itself.
data "aws_iam_policy_document" "clearledger_permission_boundary" {
  statement {
    sid    = "DenyEc2IamS3LambdaDynamo"
    effect = "Deny"
    # Why: ClearLedger app pods never manage raw EC2, IAM users, S3 buckets, or
    # arbitrary serverless/data APIs via these IRSA identities.
    actions = [
      "ec2:*",
      "iam:*",
      "s3:*",
      "lambda:*",
      "dynamodb:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "clearledger_permission_boundary" {
  name        = "${var.project_name}-permission-boundary"
  description = "Permission boundary for ClearLedger IRSA roles — caps AWS API surface"
  policy      = data.aws_iam_policy_document.clearledger_permission_boundary.json

  tags = {
    Name = "${var.project_name}-permission-boundary"
  }
}

# ── auth-service IRSA ─────────────────────────────────────────────────────────
data "aws_iam_policy_document" "app_auth_irsa_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    # Why StringEquals on :sub: only this exact Kubernetes SA in this namespace may assume.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:clearledger:auth-service"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "app_auth_irsa_permissions" {
  statement {
    sid    = "AllowAuthSecretOnly"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.auth_service.arn]
  }

  statement {
    sid    = "DenyReadingPostgresSecret"
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.postgres.arn]
  }

  statement {
    sid    = "DenyReadingLedgerSecret"
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.ledger_service.arn]
  }
}

resource "aws_iam_role" "app_auth_irsa" {
  name                 = "${var.project_name}-auth-service"
  assume_role_policy   = data.aws_iam_policy_document.app_auth_irsa_assume.json
  permissions_boundary = aws_iam_policy.clearledger_permission_boundary.arn

  tags = {
    Name = "${var.project_name}-auth-service-irsa"
  }
}

resource "aws_iam_role_policy" "app_auth_irsa_permissions" {
  name   = "${var.project_name}-auth-service-irsa-inline"
  role   = aws_iam_role.app_auth_irsa.id
  policy = data.aws_iam_policy_document.app_auth_irsa_permissions.json
}

# ── ledger-service IRSA ──────────────────────────────────────────────────────
data "aws_iam_policy_document" "app_ledger_irsa_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:clearledger:ledger-service"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "app_ledger_irsa_permissions" {
  statement {
    sid    = "AllowLedgerSecretOnly"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.ledger_service.arn]
  }

  statement {
    sid    = "DenyReadingPostgresSecret"
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.postgres.arn]
  }

  statement {
    sid    = "DenyReadingAuthSecret"
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [aws_secretsmanager_secret.auth_service.arn]
  }
}

resource "aws_iam_role" "app_ledger_irsa" {
  name                 = "${var.project_name}-ledger-service"
  assume_role_policy   = data.aws_iam_policy_document.app_ledger_irsa_assume.json
  permissions_boundary = aws_iam_policy.clearledger_permission_boundary.arn

  tags = {
    Name = "${var.project_name}-ledger-service-irsa"
  }
}

resource "aws_iam_role_policy" "app_ledger_irsa_permissions" {
  name   = "${var.project_name}-ledger-service-irsa-inline"
  role   = aws_iam_role.app_ledger_irsa.id
  policy = data.aws_iam_policy_document.app_ledger_irsa_permissions.json
}

# ── notification-service IRSA (no Secrets Manager — Redis only in app) ───────
data "aws_iam_policy_document" "app_notification_irsa_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:sub"
      values   = ["system:serviceaccount:clearledger:notification-service"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Minimal identity policy — notification-service talks to Redis only; no SM API calls.
data "aws_iam_policy_document" "app_notification_irsa_permissions" {
  statement {
    sid    = "WhoAmIOnly"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
    ]
    # STS GetCallerIdentity uses resource "*"; it does not grant Secrets Manager access.
    resources = ["*"]
  }
}

resource "aws_iam_role" "app_notification_irsa" {
  name                 = "${var.project_name}-notification-service"
  assume_role_policy   = data.aws_iam_policy_document.app_notification_irsa_assume.json
  permissions_boundary = aws_iam_policy.clearledger_permission_boundary.arn

  tags = {
    Name = "${var.project_name}-notification-service-irsa"
  }
}

resource "aws_iam_role_policy" "app_notification_irsa_permissions" {
  name   = "${var.project_name}-notification-service-irsa-inline"
  role   = aws_iam_role.app_notification_irsa.id
  policy = data.aws_iam_policy_document.app_notification_irsa_permissions.json
}

# ── GitHub Actions OIDC — keyless ECR push ───────────────────────────────────
# Why: no AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY stored in GitHub Secrets.
# GitHub mints a short-lived OIDC token per job; AWS trusts it via this provider.
# The pipeline assumes this role to push images to ECR and nothing else.

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  # Audience claim GitHub uses when minting OIDC tokens for AWS.
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC CA thumbprint — stable, published by GitHub.
  # https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "${var.project_name}-github-actions-oidc"
  }
}

data "aws_iam_policy_document" "github_actions_ecr_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Why StringEquals on the GitHub Environment subject:
    # The AWS role can only be assumed by jobs running in the protected
    # `production` environment of YOUR_GITHUB_USERNAME/clearledger. In GitHub, protect
    # that environment with required reviewers and branch restrictions.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:YOUR_GITHUB_USERNAME/clearledger:environment:production"]
    }
  }
}

data "aws_iam_policy_document" "github_actions_ecr_permissions" {
  statement {
    sid    = "ECRAuth"
    effect = "Allow"
    # GetAuthorizationToken has no resource ARN — it returns a registry-level token.
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid    = "ECRPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    # Scoped to only the ClearLedger ECR repos — not every repo in the account.
    resources = [for repo in aws_ecr_repository.services : repo.arn]
  }
}

resource "aws_iam_role" "github_actions_ecr" {
  name               = "${var.project_name}-github-actions-ecr"
  assume_role_policy = data.aws_iam_policy_document.github_actions_ecr_assume.json

  tags = {
    Name = "${var.project_name}-github-actions-ecr"
  }
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  name   = "${var.project_name}-github-actions-ecr-inline"
  role   = aws_iam_role.github_actions_ecr.id
  policy = data.aws_iam_policy_document.github_actions_ecr_permissions.json
}

# ── Developer read-only (human assume) ──────────────────────────────────────
data "aws_iam_policy_document" "developer_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type = "AWS"
      # Why account root: lab-friendly trust — restrict in production with
      # aws:PrincipalArn conditions, SAML/OIDC, or AWS SSO permission sets.
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "developer_readonly" {
  name                 = "${var.project_name}-developer-readonly"
  assume_role_policy   = data.aws_iam_policy_document.developer_assume.json
  permissions_boundary = aws_iam_policy.clearledger_permission_boundary.arn

  tags = {
    Name = "${var.project_name}-developer-readonly"
  }
}

resource "aws_iam_role_policy_attachment" "developer_readonly_managed" {
  role       = aws_iam_role.developer_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "developer_deny_secrets" {
  statement {
    sid    = "DenySecretsManager"
    effect = "Deny"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
      "secretsmanager:PutSecretValue",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "developer_deny_secrets" {
  name   = "${var.project_name}-developer-deny-secrets"
  role   = aws_iam_role.developer_readonly.id
  policy = data.aws_iam_policy_document.developer_deny_secrets.json
}
