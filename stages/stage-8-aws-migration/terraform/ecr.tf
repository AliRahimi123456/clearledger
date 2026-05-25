# INTRODUCED: Stage 8 — AWS Migration
# PURPOSE: ECR repositories for all three ClearLedger services.
#          Replaces Docker Hub usage from Stages 0-7.

locals {
  ecr_repos = [
    "${var.project_name}/auth-service",
    "${var.project_name}/ledger-service",
    "${var.project_name}/notification-service",
  ]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.ecr_repos)

  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  # Why IMMUTABLE: prevents overwriting a tag — critical for supply chain integrity.
  # In CI, images are tagged with the git SHA (e.g., :abc1234). Immutable tags
  # ensure :abc1234 always refers to the exact image that passed security gates.

  image_scanning_configuration {
    scan_on_push = true
    # Why: ECR basic scanning catches known CVEs at push time as a second gate
    # behind Trivy in CI. Defense in depth.
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = each.value
  }
}

# Lifecycle policy: keep last 10 tagged images per repo, expire untagged after 7 days.
# Why: ECR storage costs $0.10/GB/month. Untagged images from failed builds accumulate.
resource "aws_ecr_lifecycle_policy" "services" {
  for_each   = aws_ecr_repository.services
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 10 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
    ]
  })
}
