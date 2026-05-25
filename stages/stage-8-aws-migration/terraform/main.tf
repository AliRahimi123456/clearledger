# INTRODUCED: Stage 8 — AWS Migration
# PURPOSE: Provider configuration, required versions, S3 backend, and input variables

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Uncomment to store state in S3 for team sharing.
  # Create the bucket and DynamoDB table first — Terraform cannot create its own backend.
  # Run: aws s3 mb s3://YOUR-BUCKET --region eu-west-1
  # Run: aws dynamodb create-table --table-name terraform-state-lock \
  #        --attribute-definitions AttributeName=LockID,AttributeType=S \
  #        --key-schema AttributeName=LockID,KeyType=HASH \
  #        --billing-mode PAY_PER_REQUEST --region eu-west-1
  #
  # backend "s3" {
  #   bucket         = "YOUR-TERRAFORM-STATE-BUCKET"
  #   key            = "clearledger/terraform.tfstate"
  #   region         = "eu-west-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  # default_tags applies Project/Stage/ManagedBy to every resource automatically.
  # Why: ensures all AWS resources are identifiable and cost-attributable.
  default_tags {
    tags = {
      Project     = var.project_name
      Stage       = "8"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# Why: the Helm provider authenticates to EKS using the AWS CLI exec plugin.
# This avoids storing kubeconfig credentials in Terraform state.
provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.main.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.main.name, "--region", var.aws_region]
    }
  }
}

# ── Data sources ──────────────────────────────────────────────────────────────
# Why: data sources avoid hardcoding account IDs and region strings.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy ClearLedger infrastructure"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Project name — used as a prefix for all resource names and tags"
  type        = string
  default     = "clearledger"
}

variable "environment" {
  description = "Deployment environment label (prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS managed node group worker nodes"
  type        = string
  default     = "t3.medium"
  # Why t3.medium: minimum size that runs the full ClearLedger stack with headroom.
  # t3.small (2GB RAM) is too tight once Falco and Kyverno sidecars are included.
}

variable "eks_node_count" {
  description = "Number of EKS worker nodes"
  type        = number
  default     = 3
  # Why 3: minimum for pod anti-affinity across AZs. Reduce to 2 to save cost.
}
