locals {
  name   = var.name
  region = var.region
  
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/awslabs/data-on-eks"
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

#---------------------------------------------------------------
# VPC using base module
#---------------------------------------------------------------
module "vpc" {
  source = "../../../../base/vpc"
  
  name          = local.name
  vpc_cidr      = var.vpc_cidr
  secondary_cidrs = var.secondary_cidrs
  
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"         = local.name
  }

  tags = local.tags
}

#---------------------------------------------------------------
# EKS Cluster using base module
#---------------------------------------------------------------
module "eks" {
  source = "../../../../base/eks"
  
  name                           = local.name
  eks_cluster_version            = var.eks_cluster_version
  cluster_endpoint_public_access = var.cluster_endpoint_public_access
  
  vpc_id                        = module.vpc.vpc_id
  private_subnets               = module.vpc.private_subnets
  private_subnets_cidr_blocks   = module.vpc.private_subnets_cidr_blocks
  
  kms_key_admin_roles = var.kms_key_admin_roles
  
  managed_node_groups = {
    # Core node group for system workloads
    core_node_group = {
      name        = "core-node-group"
      description = "EKS managed node group for core workloads"
      
      # Filtering only Secondary CIDR private subnets starting with "100."
      subnet_ids = compact([for subnet_id, cidr_block in zipmap(module.vpc.private_subnets, module.vpc.private_subnets_cidr_blocks) :
        substr(cidr_block, 0, 4) == "100." ? subnet_id : null]
      )

      min_size     = 3
      max_size     = 9
      desired_size = 3

      instance_types = ["m5.xlarge"]

      labels = {
        WorkerType    = "ON_DEMAND"
        NodeGroupType = "core"
      }

      tags = {
        Name                     = "core-node-grp"
        "karpenter.sh/discovery" = local.name
      }
    }
  }
  
  enable_mountpoint_s3_csi        = var.enable_mountpoint_s3_csi
  enable_cloudwatch_observability = var.enable_cloudwatch_observability
  enable_argocd                   = true
  argocd_chart_version            = "7.7.12"
  argocd_domain                   = "${local.name}-argocd.local"
  
  tags = local.tags
}

#---------------------------------------------------------------
# Providers using base module
#---------------------------------------------------------------
module "providers" {
  source = "../../../../base/providers"
  
  region = local.region
  cluster_endpoint = module.eks.cluster_endpoint
  cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
  cluster_auth_token = module.eks.cluster_auth_token
}

#---------------------------------------------------------------
# S3 bucket for Spark Event Logs
#---------------------------------------------------------------
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 4.6"

  bucket_prefix = "${local.name}-spark-logs-"

  # For example only - please evaluate for your environment
  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = local.tags
}

# Creating an s3 bucket prefix for Spark History event logs
resource "aws_s3_object" "spark_event_logs" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "spark-event-logs/"
  content_type = "application/x-directory"
}

#---------------------------------------------------------------
# IAM Policies for Spark workloads
#---------------------------------------------------------------
data "aws_iam_policy_document" "spark_operator" {
  statement {
    sid       = "S3Access"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::*"]

    actions = [
      "s3:DeleteObject",
      "s3:DeleteObjectVersion", 
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
  }

  statement {
    sid       = "CloudWatchLogsAccess"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:*"]

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream", 
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
  }
}

resource "aws_iam_policy" "spark_operator" {
  name_prefix = "${local.name}-spark-operator"
  path        = "/"
  description = "IAM policy for Spark job execution"
  policy      = data.aws_iam_policy_document.spark_operator.json
  tags        = local.tags
}