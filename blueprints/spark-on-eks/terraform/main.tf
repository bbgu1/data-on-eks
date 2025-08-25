locals {
  name   = var.name
  region = var.region

  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = merge(var.tags, {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  })
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Data sources for cluster authentication
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks_blueprint.cluster_name
}

#---------------------------------------------------------------
# Provider Configurations
#---------------------------------------------------------------

# Configure AWS Provider
provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# ECR always authenticates with us-east-1 region
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

# Configure Kubernetes Provider
provider "kubernetes" {
  host                   = module.eks_blueprint.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprint.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Configure Helm Provider
provider "helm" {
  kubernetes {
    host                   = module.eks_blueprint.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprint.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# Configure kubectl Provider
provider "kubectl" {
  apply_retry_count      = 10
  host                   = module.eks_blueprint.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprint.cluster_certificate_authority_data)
  load_config_file       = false
  token                  = data.aws_eks_cluster_auth.cluster.token
}

#---------------------------------------------------------------
# VPC using base module
#---------------------------------------------------------------
module "vpc_blueprint" {
  source = "../../../infra/terraform/vpc"

  name            = local.name
  vpc_cidr        = var.vpc_cidr
  secondary_cidrs = var.secondary_cidrs

  tags = local.tags
}

#---------------------------------------------------------------
# EKS Cluster, Karpenter and ArgoCD Deployment Module
#---------------------------------------------------------------
module "eks_blueprint" {
  source = "../../../infra/terraform/eks"

  name                           = local.name
  eks_cluster_version            = var.eks_cluster_version
  cluster_endpoint_public_access = var.cluster_endpoint_public_access

  vpc_id                      = module.vpc_blueprint.vpc_id
  private_subnets             = module.vpc_blueprint.private_subnets
  private_subnets_cidr_blocks = module.vpc_blueprint.private_subnets_cidr_blocks

  kms_key_admin_roles = var.kms_key_admin_roles

  tags = local.tags
}

# ==============================================================================
# ArgoCD Applications - Deployed via kubectl_manifest with terraform
# ==============================================================================

module "argocd_addons" {
  source = "../../../infra/terraform/argocd-addons"

  oidc_provider_arn             = module.eks_blueprint.oidc_provider_arn
  cluster_name                  = module.eks_blueprint.cluster_name
  karpenter_node_iam_role_name  = module.eks_blueprint.karpenter_node_iam_role_name

  enable_spark_history_server = true
  spark_history_server_helm_config = {
    values = [
      <<-EOT
        logStore:
          type: "s3"
          s3:
            bucket: ${module.s3_bucket.s3_bucket_id}
            eventLogsPath: "spark-event-logs/"
        EOT
    ]
  }

  # Spark Operator
  enable_spark_operator = true
  spark_operator_helm_config = {
    values = [
      <<-EOT
        batchScheduler:
          enable: true
          default: "yunikorn"
        spark:
          jobNamespaces:
            - ""  # Empty string allows all namespaces
          serviceAccount:
            create: false
          rbac:
            create: false
      EOT
    ]
  }

  # Apache YuniKorn Scheduler
  enable_yunikorn = true

  enable_karpenter_resources = true
}
