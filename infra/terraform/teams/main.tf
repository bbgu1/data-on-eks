#---------------------------------------------------------------
# Data Sources
#---------------------------------------------------------------

data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

#---------------------------------------------------------------
# IAM Roles for Teams with Pod Identity
#---------------------------------------------------------------

resource "aws_iam_role" "team" {
  for_each = var.teams

  name = "${var.name_prefix}-${each.value.name}-pod-identity-role"

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

  tags = merge(
    var.tags,
    each.value.tags,
    {
      "Name" = "${var.name_prefix}-${each.value.name}-pod-identity-role"
      "Team" = each.value.name
    }
  )
}

#---------------------------------------------------------------
# Attach Policies to Team Roles
#---------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "team_policies" {
  for_each = local.team_policy_attachments

  role       = aws_iam_role.team[each.value.team_name].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy_attachment" "team_additional_policies" {
  for_each = local.team_additional_policy_attachments

  role       = aws_iam_role.team[each.value.team_name].name
  policy_arn = each.value.policy_arn
}

#---------------------------------------------------------------
# Pod Identity Associations
#---------------------------------------------------------------

resource "aws_eks_pod_identity_association" "team" {
  for_each = var.teams

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.team[each.key].arn

  tags = merge(
    var.tags,
    each.value.tags,
    {
      "Name" = "${var.name_prefix}-${each.value.name}-pod-identity"
      "Team" = each.value.name
    }
  )
}

#---------------------------------------------------------------
# Local Values for Policy Attachments
#---------------------------------------------------------------

locals {
  # Flatten team policies for for_each
  team_policy_attachments = merge([
    for team_name, team_config in var.teams : {
      for idx, policy_arn in team_config.iam_policy_arns :
      "${team_name}-${idx}" => {
        team_name  = team_name
        policy_arn = policy_arn
      }
    }
  ]...)

  # Flatten team additional policies for for_each
  team_additional_policy_attachments = merge([
    for team_name, team_config in var.teams : {
      for policy_name, policy_arn in team_config.additional_policies :
      "${team_name}-${policy_name}" => {
        team_name  = team_name
        policy_arn = policy_arn
      }
    }
  ]...)
}
