# INTRODUCED: Stage 8 — AWS Migration
# PURPOSE: AWS Secrets Manager secrets for ClearLedger credentials.
#          Replaces HashiCorp Vault (Stage 5) for the AWS deployment.
#          Secrets are consumed by External Secrets Operator (ESO) running
#          in the cluster — the application code does not change.

# ─────────────────────────────────────────────────────────────────────────────
# IMPORTANT: Change CHANGE_ME_BEFORE_APPLY values before running terraform apply.
# These are the actual credentials that will be used by the running services.
# ─────────────────────────────────────────────────────────────────────────────

# ── PostgreSQL credentials ────────────────────────────────────────────────────
# Change this value before running terraform apply
resource "aws_secretsmanager_secret" "postgres" {
  name        = "${var.project_name}/postgres"
  description = "ClearLedger PostgreSQL master credentials"

  # Why: 7-day recovery window prevents accidental permanent deletion.
  # Set to 0 to disable recovery (faster destroy in lab — not recommended in prod).
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}/postgres"
  }
}

resource "aws_secretsmanager_secret_version" "postgres" {
  secret_id = aws_secretsmanager_secret.postgres.id
  # Change CHANGE_ME_BEFORE_APPLY to a strong password before terraform apply
  secret_string = jsonencode({
    username = "clearledger"
    password = "CHANGE_ME_BEFORE_APPLY"
  })

  lifecycle {
    # Why ignore_changes: after initial creation, the password may be rotated
    # outside Terraform. Ignore changes so Terraform doesn't revert rotations.
    ignore_changes = [secret_string]
  }
}

# ── Auth service secrets ──────────────────────────────────────────────────────
# Change this value before running terraform apply
resource "aws_secretsmanager_secret" "auth_service" {
  name        = "${var.project_name}/auth-service"
  description = "ClearLedger auth-service JWT signing secret"

  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}/auth-service"
  }
}

resource "aws_secretsmanager_secret_version" "auth_service" {
  secret_id = aws_secretsmanager_secret.auth_service.id
  # Change CHANGE_ME_BEFORE_APPLY values before terraform apply
  # Generate jwt_secret with: openssl rand -base64 64
  secret_string = jsonencode({
    jwt_secret   = "CHANGE_ME_BEFORE_APPLY"
    database_url = "postgresql://clearledger:CHANGE_ME_BEFORE_APPLY@PLACEHOLDER_RDS:5432/clearledger"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ── Ledger service secrets ────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "ledger_service" {
  name        = "${var.project_name}/ledger-service"
  description = "ClearLedger ledger-service credentials (IRSA-scoped read in iam.tf)"

  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}/ledger-service"
  }
}

resource "aws_secretsmanager_secret_version" "ledger_service" {
  secret_id = aws_secretsmanager_secret.ledger_service.id
  secret_string = jsonencode({
    database_url = "postgresql://clearledger:CHANGE_ME_BEFORE_APPLY@PLACEHOLDER_RDS:5432/clearledger"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ── Outputs: ARNs only (never output secret values) ──────────────────────────

output "postgres_secret_arn" {
  description = "ARN of the PostgreSQL credentials secret in Secrets Manager"
  value       = aws_secretsmanager_secret.postgres.arn
}

output "auth_service_secret_arn" {
  description = "ARN of the auth-service JWT secret in Secrets Manager"
  value       = aws_secretsmanager_secret.auth_service.arn
}

output "ledger_service_secret_arn" {
  description = "ARN of the ledger-service secret in Secrets Manager"
  value       = aws_secretsmanager_secret.ledger_service.arn
}
