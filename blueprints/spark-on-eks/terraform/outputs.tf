output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks_blueprint.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks_blueprint.cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = module.eks_blueprint.cluster_version
}

output "region" {
  description = "AWS region"
  value       = local.region
}

output "vpc_id" {
  description = "ID of the VPC where cluster is deployed"
  value       = module.vpc_blueprint.vpc_id
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc_blueprint.private_subnets
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for the EKS cluster"
  value       = module.eks_blueprint.oidc_provider_arn
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks_blueprint.cluster_name}"
}

output "spark_teams_roles" {
  description = "Map of Spark team names to their Pod Identity role ARNs"
  value       = module.spark_teams.team_roles
}

output "spark_teams_associations" {
  description = "Map of Spark team Pod Identity association details"
  value       = module.spark_teams.pod_identity_associations
}

output "s3_bucket_name" {
  description = "S3 Bucket for Spark Logs"
  value = module.s3_bucket.s3_bucket_id
}

output "karpenter_sqs_queue_name" {
  description = "Karpenter SQS interruption queue name"
  value = module.eks_blueprint.karpenter_sqs_queue_name
}

output "karpenter_node_node_iam_role_arn" {
  description = "Karpenter node IAM Role ARN"
  value       = module.eks_blueprint.karpenter_node_iam_role_arn
}

output "karpenter_node_instance_profile_name" {
  description = "Karpenter node instance profile name"
  value       = module.eks_blueprint.karpenter_node_instance_profile
}
