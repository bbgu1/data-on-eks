
# Required locals and data sources
locals {
  partition = data.aws_partition.current.partition
  karpenter_enable_spot_termination = true
}

# EC2 spot instance interruption event patterns
locals {
  ec2_events = {
    health = {
      name        = "HealthEvent"
      description = "Karpenter interrupt - AWS health event"
      event_pattern = {
        source      = ["aws.health"]
        detail-type = ["AWS Health Event"]
      }
    }
    spot = {
      name        = "SpotInterrupt"
      description = "Karpenter interrupt - EC2 spot instance interruption warning"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Spot Instance Interruption Warning"]
      }
    }
    rebalance = {
      name        = "RebalanceRecommend"
      description = "Karpenter interrupt - EC2 instance rebalance recommendation"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance Rebalance Recommendation"]
      }
    }
    state_change = {
      name        = "StateChange"
      description = "Karpenter interrupt - EC2 instance state-change notification"
      event_pattern = {
        source      = ["aws.ec2"]
        detail-type = ["EC2 Instance State-change Notification"]
      }
    }
  }
}

data "aws_partition" "current" {}

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


# Attach Karpenter policy to the role
resource "aws_iam_role_policy_attachment" "karpenter_pod_identity_policy" {
  policy_arn = aws_iam_policy.karpenter_policy.arn
  role       = aws_iam_role.karpenter_pod_identity_role.name
}

# Karpenter IAM Policy - Complete Policy with All Required Permissions
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
      },
      {
        Sid    = "AllowScopedInstanceActionsWithTags"
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DeleteLaunchTemplate",
          "ec2:RunInstances"
        ]
        Resource = [
          "arn:${local.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*",
          "arn:${local.partition}:ec2:${data.aws_region.current.name}::image/*"
        ]
      },
      {
        Sid      = "AllowScopedInstanceTermination"
        Effect   = "Allow"
        Action   = "ec2:TerminateInstances"
        Resource = "arn:${local.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*"
        Condition = {
          StringLike = {
            "ec2:ResourceTag/kubernetes.io/cluster/${var.name}" = "*"
          }
        }
      },
      {
        Sid      = "AllowEKSClusterAccess"
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = "arn:${local.partition}:eks:*:${data.aws_caller_identity.current.account_id}:cluster/${var.name}"
      },
      {
        Sid      = "AllowPassNodeInstanceRole"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = try(module.eks.eks_managed_node_groups.initial.iam_role_arn, "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*-node-group-*")
      },
      {
        Sid    = "AllowSSMParameterAccess"
        Effect = "Allow"
        Action = "ssm:GetParameter"
        Resource = "arn:${local.partition}:ssm:*:*:parameter/aws/service/*"
      },
      {
        Sid    = "AllowPricing"
        Effect = "Allow"
        Action = "pricing:GetProducts"
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
        Resource = module.karpenter_sqs.queue_arn
      }
    ]
  })

  tags = var.tags
}

# SQS queue for Karpenter interruption handling
module "karpenter_sqs" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "4.0.1"

  create = local.karpenter_enable_spot_termination

  name = "karpenter-${var.name}"

  message_retention_seconds       = 300
  sqs_managed_sse_enabled        = true
  
  create_queue_policy = true
  queue_policy_statements = {
    account = {
      sid     = "SendEventsToQueue"
      actions = ["sqs:SendMessage"]

      principals = [
        {
          type = "Service"
          identifiers = [
            "events.amazonaws.com",
            "sqs.amazonaws.com",
          ]
        }
      ]
    }
  }

  tags = var.tags
}

# CloudWatch Event Rules for Karpenter interruption handling
resource "aws_cloudwatch_event_rule" "karpenter" {
  for_each = { for k, v in local.ec2_events : k => v if local.karpenter_enable_spot_termination }

  name_prefix   = "Karpenter-${each.value.name}-"
  description   = each.value.description
  event_pattern = jsonencode(each.value.event_pattern)

  tags = merge(
    { "ClusterName" : var.name },
    var.tags,
  )
}

resource "aws_cloudwatch_event_target" "karpenter" {
  for_each = { for k, v in local.ec2_events : k => v if local.karpenter_enable_spot_termination }

  rule      = aws_cloudwatch_event_rule.karpenter[each.key].name
  target_id = "KarpenterQueueTarget"
  arn       = module.karpenter_sqs.queue_arn
}
