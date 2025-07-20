output "cluster_name" {
  description = "EKS cluster name"
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

output "region" {
  description = "AWS region"
  value       = local.region
}

output "vpc_id" {
  description = "ID of the VPC where cluster is deployed"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "s3_bucket_name" {
  description = "S3 bucket name for Spark logs"
  value       = module.s3_bucket.s3_bucket_id
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for the EKS cluster"
  value       = module.eks.oidc_provider_arn
}

output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = module.eks.argocd_namespace
}

output "argocd_server_endpoint" {
  description = "ArgoCD server endpoint"
  value       = module.eks.argocd_server_endpoint
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "configure_argocd" {
  description = "Configure ArgoCD: Port forward to access ArgoCD UI"
  value       = "kubectl port-forward svc/argocd-server -n ${module.eks.argocd_namespace} 8080:443"
}

output "karpenter_irsa_role_arn" {
  description = "Karpenter IRSA role ARN for ArgoCD applications"
  value       = module.eks.karpenter_irsa_role_arn
}

output "karpenter_node_instance_profile" {
  description = "Karpenter node instance profile for EC2NodeClass"
  value       = module.eks.karpenter_node_instance_profile
}

output "spark_operator_irsa_role_arn" {
  description = "Spark Operator IRSA role ARN"
  value       = module.eks.spark_operator_irsa_role_arn
}

output "argocd_values_example" {
  description = "Example values for ArgoCD applications"
  value = {
    clusterName             = module.eks.cluster_name
    clusterEndpoint         = module.eks.cluster_endpoint
    region                  = local.region
    s3BucketName           = module.s3_bucket.s3_bucket_id
    karpenterIrsaRoleArn   = module.eks.karpenter_irsa_role_arn
    sparkOperatorIrsaRoleArn = module.eks.spark_operator_irsa_role_arn
    vpcId                  = module.vpc.vpc_id
  }
}