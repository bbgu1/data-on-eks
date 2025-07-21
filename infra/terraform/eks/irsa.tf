#---------------------------------------------------------------
# Pod Identity Roles - Modern IRSA Replacement
#---------------------------------------------------------------

# Karpenter Pod Identity Role
resource "aws_iam_role" "karpenter_pod_identity_role" {
  name = "${var.name}-karpenter-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  managed_policy_arns = [aws_iam_policy.karpenter_policy.arn]
  tags = var.tags
}

# Pod Identity Association for Karpenter
resource "aws_eks_pod_identity_association" "karpenter" {
  cluster_name    = module.eks.cluster_name
  namespace       = "karpenter"
  service_account = "karpenter"
  role_arn        = aws_iam_role.karpenter_pod_identity_role.arn

  tags = var.tags
}

# Karpenter Node Instance Profile for v1.6
resource "aws_iam_instance_profile" "karpenter_node_instance_profile" {
  name = "KarpenterNodeInstanceProfile-${var.name}"
  role = try(
    values(module.eks.eks_managed_node_groups)[0].iam_role_name,
    module.eks.eks_managed_node_groups_defaults.iam_role_name
  )
  
  tags = var.tags
}

# Karpenter IAM Policy - Least Privilege
resource "aws_iam_policy" "karpenter_policy" {
  name_prefix = "${var.name}-karpenter"
  description = "Karpenter policy for ${var.name}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceActions"
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = [data.aws_region.current.name]
          }
        }
      },
      {
        Sid    = "AllowScopedInstanceActionsWithTags"
        Effect = "Allow"
        Action = [
          "ec2:RunInstances",
          "ec2:TerminateInstances"
        ]
        Resource = [
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:volume/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:network-interface/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:launch-template/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:security-group/*",
          "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:subnet/*"
        ]
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = [data.aws_region.current.name]
          }
        }
      },
      {
        Sid      = "AllowEKSClusterAccess"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = module.eks.cluster_arn
      },
      {
        Sid    = "AllowPassNodeInstanceRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/eksctl-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Sid    = "AllowCreateDeleteLaunchTemplate"
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:DeleteLaunchTemplate"
        ]
        Resource = "arn:aws:ec2:*:${data.aws_caller_identity.current.account_id}:launch-template/*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = [data.aws_region.current.name]
          }
        }
      },
      {
        Sid    = "AllowCreateTags"
        Effect = "Allow"
        Action = "ec2:CreateTags"
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = [
              "RunInstances",
              "CreateFleet",
              "CreateLaunchTemplate"
            ]
          }
        }
      },
      {
        Sid    = "AllowPricing"
        Effect = "Allow"
        Action = [
          "pricing:GetProducts"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowInterruptionQueueActions"
        Effect = "Allow"
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage"
        ]
        Resource = "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.name}"
      }
    ]
  })

  tags = var.tags
}

# EBS CSI Driver Pod Identity Role
resource "aws_iam_role" "ebs_csi_pod_identity_role" {
  name = "${var.name}-ebs-csi-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
  tags = var.tags
}

# Pod Identity Association for EBS CSI Driver
resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi_pod_identity_role.arn

  tags = var.tags
}

# S3 CSI Driver Pod Identity Role
resource "aws_iam_role" "s3_csi_pod_identity_role" {
  count = var.enable_mountpoint_s3_csi ? 1 : 0
  name  = "${var.name}-s3-csi-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  managed_policy_arns = [aws_iam_policy.s3_csi_access_policy[0].arn]
  tags = var.tags
}

# Pod Identity Association for S3 CSI Driver
resource "aws_eks_pod_identity_association" "s3_csi" {
  count           = var.enable_mountpoint_s3_csi ? 1 : 0
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "s3-csi-driver-sa"
  role_arn        = aws_iam_role.s3_csi_pod_identity_role[0].arn

  tags = var.tags
}
