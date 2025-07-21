output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "The Kubernetes version for the EKS cluster"
  value       = module.eks.cluster_version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster for the OpenID Connect identity provider"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for the EKS cluster"
  value       = module.eks.oidc_provider_arn
}

output "cluster_auth_token" {
  description = "EKS cluster authentication token"
  value       = data.aws_eks_cluster_auth.this.token
  sensitive   = true
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "ID of the node shared security group"
  value       = module.eks.node_security_group_id
}

output "eks_managed_node_groups" {
  description = "Map of attribute maps for all EKS managed node groups created"
  value       = module.eks.eks_managed_node_groups
}

output "karpenter_irsa_role_arn" {
  description = "Karpenter IRSA role ARN"
  value       = try(module.karpenter_irsa.iam_role_arn, null)
}

output "karpenter_node_instance_profile" {
  description = "Karpenter node instance profile name"
  value       = try(aws_iam_instance_profile.karpenter_node_instance_profile.name, null)
}

output "spark_operator_irsa_role_arn" {
  description = "Spark Operator IRSA role ARN"
  value       = try(module.spark_operator_irsa.iam_role_arn, null)
}