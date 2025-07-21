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

output "s3_bucket_name" {
  description = "S3 bucket name for Spark logs"
  value       = module.s3_bucket.s3_bucket_id
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for the EKS cluster"
  value       = module.eks_blueprint.oidc_provider_arn
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks_blueprint.cluster_name}"
}

output "configure_argocd" {
  description = "Configure ArgoCD: Port forward to access ArgoCD UI"
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

output "karpenter_pod_identity_role_arn" {
  description = "Karpenter Pod Identity role ARN for ArgoCD applications"
  value       = module.eks_blueprint.karpenter_pod_identity_role_arn
}

output "karpenter_node_instance_profile" {
  description = "Karpenter node instance profile for EC2NodeClass"
  value       = module.eks_blueprint.karpenter_node_instance_profile
}

output "spark_operator_pod_identity_role_arn" {
  description = "Spark Operator Pod Identity role ARN"
  value       = aws_iam_role.spark_operator_pod_identity_role.arn
}

output "spark_jobs_pod_identity_role_arn" {
  description = "Spark Jobs Pod Identity role ARN"
  value       = aws_iam_role.spark_jobs_pod_identity_role.arn
}

output "s3_bucket_name" {
  description = "S3 bucket name for Spark logs"
  value       = module.s3_bucket.s3_bucket_id
}
