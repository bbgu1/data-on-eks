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


output "karpenter_sqs_queue_name" {
  description = "Karpenter SQS interruption queue name"
  value       = module.karpenter.queue_name
}

output "karpenter_node_instance_profile_name" {
  description = "Karpenter node instance profile name"
  value       = module.karpenter.instance_profile_name
}

output "karpenter_node_iam_role_arn" {
  description = "Karpenter node IAM role ARN"
  value = module.karpenter.iam_role_arn
}

output "karpenter_node_iam_role_name" {
  description = "Karpenter node IAM role name"
  value = module.karpenter.iam_role_name
}

output "ebs_csi_pod_identity_role_arn" {
  description = "EBS CSI Driver Pod Identity role ARN"
  value       = aws_iam_role.ebs_csi_pod_identity_role.arn
}

output "s3_csi_pod_identity_role_arn" {
  description = "S3 CSI Driver Pod Identity role ARN"
  value       = var.enable_mountpoint_s3_csi ? aws_iam_role.s3_csi_pod_identity_role[0].arn : null
}

output "cluster_primary_security_group_id" {
  description = "Cluster security group that was created by Amazon EKS for the cluster"
  value       = module.eks.cluster_primary_security_group_id
}
