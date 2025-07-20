#---------------------------------------------------------------
# Enhanced IRSA Roles with Least Privilege
#---------------------------------------------------------------

# Karpenter IRSA Role
module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.55"

  role_name_prefix = format("%s-%s-", var.name, "karpenter")
  
  # Custom policy instead of broad permissions
  role_policy_arns = {
    karpenter = aws_iam_policy.karpenter_policy.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }

  tags = var.tags
}

# Karpenter Node Instance Profile for v1.6
resource "aws_iam_instance_profile" "karpenter_node_instance_profile" {
  name = "KarpenterNodeInstanceProfile-${var.name}"
  role = module.eks.eks_managed_node_groups_defaults.iam_role_name
  
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

# Spark Operator IRSA Role
module "spark_operator_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.55"

  role_name_prefix = format("%s-%s-", var.name, "spark-operator")
  
  role_policy_arns = {
    spark_operator = aws_iam_policy.spark_operator_policy.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "spark-operator:spark-operator",
        "default:spark",
        "spark-team-a:spark",
        "spark-team-b:spark", 
        "spark-team-c:spark"
      ]
    }
  }

  tags = var.tags
}

# Spark Operator IAM Policy
resource "aws_iam_policy" "spark_operator_policy" {
  name_prefix = "${var.name}-spark-operator"
  description = "Spark Operator policy for ${var.name}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.name}-*",
          "arn:aws:s3:::${var.name}-*/*"
        ]
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/spark/*"
      }
    ]
  })

  tags = var.tags
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}