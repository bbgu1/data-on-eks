variable "name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "spark-k8s-operator"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "eks_cluster_version" {
  description = "EKS Cluster version"
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "secondary_cidrs" {
  description = "Secondary CIDR blocks for the VPC"
  type        = list(string)
  default     = ["100.64.0.0/16"]
}

variable "cluster_endpoint_public_access" {
  description = "Enable public access to cluster endpoint"
  type        = bool
  default     = true
}

variable "kms_key_admin_roles" {
  description = "A list of IAM roles that will have admin access to the KMS key"
  type        = list(string)
  default     = []
}

variable "enable_mountpoint_s3_csi" {
  description = "Enable AWS Mountpoint S3 CSI driver"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_observability" {
  description = "Enable Amazon CloudWatch Observability addon"
  type        = bool
  default     = true
}

variable "enable_yunikorn" {
  description = "Enable Apache YuniKorn scheduler"
  type        = bool
  default     = false
}

variable "enable_jupyterhub" {
  description = "Enable JupyterHub"
  type        = bool
  default     = false
}