#---------------------------------------------------------------
# Teams Module Outputs
#---------------------------------------------------------------

output "team_roles" {
  description = "Map of team names to IAM role ARNs"
  value = {
    for team_name, team_config in var.teams :
    team_name => aws_iam_role.team[team_name].arn
  }
}

output "team_role_names" {
  description = "Map of team names to IAM role names"
  value = {
    for team_name, team_config in var.teams :
    team_name => aws_iam_role.team[team_name].name
  }
}

output "pod_identity_associations" {
  description = "Map of team names to Pod Identity association details"
  value = {
    for team_name, team_config in var.teams :
    team_name => {
      association_arn = aws_eks_pod_identity_association.team[team_name].association_arn
      association_id  = aws_eks_pod_identity_association.team[team_name].association_id
      cluster_name    = aws_eks_pod_identity_association.team[team_name].cluster_name
      namespace       = aws_eks_pod_identity_association.team[team_name].namespace
      service_account = aws_eks_pod_identity_association.team[team_name].service_account
      role_arn        = aws_eks_pod_identity_association.team[team_name].role_arn
    }
  }
}

output "team_configs" {
  description = "Original team configurations for reference"
  value = {
    for team_name, team_config in var.teams :
    team_name => {
      name            = team_config.name
      namespace       = team_config.namespace
      service_account = team_config.service_account
      role_arn        = aws_iam_role.team[team_name].arn
    }
  }
}
