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
  value       = aws_s3_bucket.spark.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN for Spark logs"
  value       = aws_s3_bucket.spark.arn
}

output "oidc_provider_arn" {
  description = "The ARN of the OIDC provider for the EKS cluster"
  value       = module.eks.oidc_provider_arn
}

output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "configure_argocd" {
  description = "Configure ArgoCD: Port forward to access ArgoCD UI"
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:443"
}

output "argocd_admin_password" {
  description = "Get ArgoCD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
  sensitive   = true
}

output "grafana_admin_password" {
  description = "Grafana admin password from AWS Secrets Manager"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.grafana.name} --region ${local.region} --query SecretString --output text"
  sensitive   = true
}

output "karpenter_node_iam_role_arn" {
  description = "Karpenter node IAM role ARN"
  value       = module.eks.karpenter_node_iam_role_arn
}

output "karpenter_node_instance_profile" {
  description = "Karpenter node instance profile for EC2NodeClass"
  value       = module.eks.karpenter_node_instance_profile_name
}

output "spark_operator_pod_identity_role_arn" {
  description = "Spark Operator Pod Identity role ARN"
  value       = aws_iam_role.spark_operator.arn
}

output "spark_jobs_pod_identity_role_arn" {
  description = "Spark Jobs Pod Identity role ARN"
  value       = aws_iam_role.spark_jobs.arn
}

# Access URLs
output "access_urls" {
  description = "URLs to access various services"
  value = {
    argocd              = "http://argocd.${local.name}.local (after kubectl port-forward svc/argocd-server -n argocd 8080:80)"
    grafana             = "http://grafana.${local.name}.local (after ingress setup)"
    spark_history       = "http://spark-history.${local.name}.local (after ingress setup)"
    yunikorn           = "http://yunikorn.${local.name}.local (after ingress setup)"
  }
}

# Useful commands
output "useful_commands" {
  description = "Useful commands for operating the cluster"
  value = {
    get_argocd_apps     = "kubectl get applications -n argocd"
    get_spark_jobs      = "kubectl get sparkapplications -A"
    get_karpenter_nodes = "kubectl get nodepools -n karpenter"
    get_grafana_secret  = aws_secretsmanager_secret.grafana.name
  }
}