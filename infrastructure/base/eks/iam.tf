#---------------------------------------------------------------
# EKS Amazon CloudWatch Observability Role
#---------------------------------------------------------------
resource "aws_iam_role" "cloudwatch_observability_role" {
  count = var.enable_cloudwatch_observability ? 1 : 0
  name  = "${var.name}-eks-cw-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" : "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent",
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability_policy_attachment" {
  count      = var.enable_cloudwatch_observability ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_observability_role[0].name
}

#---------------------------------------------------------------
# IRSA for EBS CSI Driver
#---------------------------------------------------------------
module "ebs_csi_driver_irsa" {
  source                = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version               = "~> 5.55"
  role_name_prefix      = format("%s-%s-", var.name, "ebs-csi-driver")
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = var.tags
}

#---------------------------------------------------------------
# IRSA for Mountpoint S3 CSI Driver
#---------------------------------------------------------------
module "s3_csi_driver_irsa" {
  count            = var.enable_mountpoint_s3_csi ? 1 : 0
  source           = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version          = "~> 5.55"
  role_name_prefix = format("%s-%s-", var.name, "s3-csi-driver")
  role_policy_arns = {
    # WARNING: Demo purpose only. Bring your own IAM policy with least privileges
    s3_access = var.enable_mountpoint_s3_csi ? aws_iam_policy.s3_irsa_access_policy[0].arn : null
  }
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:s3-csi-driver-sa"]
    }
  }
  tags = var.tags
}

resource "aws_iam_policy" "s3_irsa_access_policy" {
  count       = var.enable_mountpoint_s3_csi ? 1 : 0
  name        = "${var.name}-S3Access"
  path        = "/"
  description = "S3 Access for Nodes"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  # checkov:skip=CKV_AWS_288: Demo purpose IAM policy
  # checkov:skip=CKV_AWS_290: Demo purpose IAM policy
  # checkov:skip=CKV_AWS_289: Demo purpose IAM policy
  # checkov:skip=CKV_AWS_355: Demo purpose IAM policy
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*",
          "s3express:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}