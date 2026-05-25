# INTRODUCED: Stage 8 — AWS Migration
# PURPOSE: Install the AWS Load Balancer Controller into the EKS cluster via Helm.
#
# Separation of concerns:
#   - This file: installs the controller (which watches for Ingress resources)
#   - infra/manifests/ingress-aws.yaml: defines the actual Ingress resource
#
# Why separate: the Ingress resource is a Kubernetes manifest managed alongside
# other app manifests in GitOps. The controller is cluster infrastructure — it
# belongs in Terraform alongside the EKS cluster that requires it.

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  # Why this annotation: links the Kubernetes service account to the IAM role
  # via IRSA. The pod can then call AWS APIs as this role without node credentials.
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.alb_controller.arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = aws_vpc.main.id
  }

  # Why: ensures the controller image is pulled from the correct regional ECR
  # account rather than Docker Hub — avoids rate limiting.
  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.${var.aws_region}.amazonaws.com/amazon/aws-load-balancer-controller"
  }

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.alb_controller,
  ]
}
