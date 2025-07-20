variable "name" {
  description = "Name to be used on all the resources as identifier"
  type        = string
}

variable "eks_cluster_version" {
  description = "Kubernetes `<major>.<minor>` version to use for the EKS cluster (i.e.: `1.31`)"
  type        = string
  default     = "1.31"
}

variable "cluster_endpoint_public_access" {
  description = "Indicates whether or not the Amazon EKS public API server endpoint is enabled"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "ID of the VPC where to create the cluster"
  type        = string
}

variable "private_subnets" {
  description = "A list of private subnet IDs where the EKS cluster will be provisioned"
  type        = list(string)
}

variable "private_subnets_cidr_blocks" {
  description = "List of cidr_blocks of private subnets"
  type        = list(string)
}

variable "kms_key_admin_roles" {
  description = "A list of IAM roles that will have admin access to the KMS key used by the cluster"
  type        = list(string)
  default     = []
}

variable "managed_node_groups" {
  description = "Map of EKS managed node group definitions to create"
  type        = any
  default     = {}
}

variable "enable_mountpoint_s3_csi" {
  description = "Enable AWS Mountpoint S3 CSI driver"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_observability" {
  description = "Enable Amazon CloudWatch Observability addon"
  type        = bool
  default     = false
}

variable "enable_argocd" {
  description = "Enable ArgoCD installation"
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.7.12"
}

variable "argocd_domain" {
  description = "ArgoCD domain name"
  type        = string
  default     = "argocd.local"
}

variable "argocd_service_type" {
  description = "ArgoCD service type"
  type        = string
  default     = "ClusterIP"
}

variable "argocd_ingress_enabled" {
  description = "Enable ArgoCD ingress"
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}