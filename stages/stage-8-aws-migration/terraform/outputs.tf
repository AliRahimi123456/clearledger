# INTRODUCED: Stage 8 — AWS Migration
# PURPOSE: Export key infrastructure values needed by aws-spinup.sh and the learner.

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "ecr_registry_url" {
  description = "ECR registry URL prefix (account.dkr.ecr.region.amazonaws.com)"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

output "auth_service_ecr_url" {
  description = "ECR repository URL for auth-service"
  value       = aws_ecr_repository.services["${var.project_name}/auth-service"].repository_url
}

output "ledger_service_ecr_url" {
  description = "ECR repository URL for ledger-service"
  value       = aws_ecr_repository.services["${var.project_name}/ledger-service"].repository_url
}

output "notification_service_ecr_url" {
  description = "ECR repository URL for notification-service"
  value       = aws_ecr_repository.services["${var.project_name}/notification-service"].repository_url
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port)"
  value       = aws_db_instance.postgres.endpoint
}

output "eso_role_arn" {
  description = "IAM role ARN for External Secrets Operator (annotate ESO service account with this)"
  value       = aws_iam_role.eso.arn
}

output "falco_role_arn" {
  description = "IAM role ARN for Falco CloudWatch log export"
  value       = aws_iam_role.falco.arn
}

output "clearledger_permission_boundary_arn" {
  description = "IAM policy ARN used as permissions boundary for ClearLedger IRSA roles"
  value       = aws_iam_policy.clearledger_permission_boundary.arn
}

output "auth_service_irsa_role_arn" {
  description = "IRSA role for auth-service ServiceAccount (Secrets Manager: auth-service secret only)"
  value       = aws_iam_role.app_auth_irsa.arn
}

output "ledger_service_irsa_role_arn" {
  description = "IRSA role for ledger-service ServiceAccount (Secrets Manager: ledger-service secret only)"
  value       = aws_iam_role.app_ledger_irsa.arn
}

output "notification_service_irsa_role_arn" {
  description = "IRSA role for notification-service (no Secrets Manager; sts:GetCallerIdentity only)"
  value       = aws_iam_role.app_notification_irsa.arn
}

output "github_actions_ecr_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC — add as GITHUB_ACTIONS_ROLE_ARN secret in github.com/YOUR_GITHUB_USERNAME/clearledger/settings/secrets/actions"
  value       = aws_iam_role.github_actions_ecr.arn
}

output "developer_readonly_role_arn" {
  description = "Human-assumable read-only role — ReadOnlyAccess + deny Secrets Manager + permission boundary"
  value       = aws_iam_role.developer_readonly.arn
}

output "alb_dns_name" {
  description = "Access ClearLedger at this URL after kubectl apply — the ALB is provisioned by the controller when the Ingress is created, not by Terraform. Run: kubectl get ingress clearledger-ingress -n clearledger -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  # Why: the ALB DNS name is only available after the Kubernetes Ingress resource
  # is applied and the controller has provisioned the load balancer (~60-90 seconds).
  # The aws-spinup.sh script fetches this value via kubectl automatically.
  value = "Retrieve after kubectl apply: kubectl get ingress clearledger-ingress -n clearledger -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "kubeconfig_command" {
  description = "Run this command to configure kubectl for the ClearLedger EKS cluster"
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.clearledger.id
}

output "cloudtrail_arn" {
  description = "CloudTrail ARN"
  value       = aws_cloudtrail.clearledger.arn
}

output "kms_key_id" {
  description = "KMS key ID used for log encryption"
  value       = aws_kms_key.clearledger.key_id
}

output "cloudwatch_log_groups" {
  description = "CloudWatch log group names (CloudTrail + VPC Flow Logs)"
  value = {
    cloudtrail    = aws_cloudwatch_log_group.cloudtrail.name
    vpc_flow_logs = aws_cloudwatch_log_group.vpc_flow_logs.name
  }
}
