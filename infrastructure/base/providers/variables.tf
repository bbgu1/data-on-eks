variable "region" {
  description = "AWS region"
  type        = string
}

variable "cluster_endpoint" {
  description = "EKS cluster endpoint"
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  type        = string
}

variable "cluster_auth_token" {
  description = "EKS cluster authentication token"
  type        = string
}