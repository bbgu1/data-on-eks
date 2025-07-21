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

# Configure providers
provider "aws" {
  region = var.region
}

# ECR always authenticates with `us-east-1` region
provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks_blueprint.cluster_name
}

provider "kubernetes" {
  host                   = module.eks_blueprint.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprint.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks_blueprint.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprint.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

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

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
    "karpenter.sh/discovery"          = local.name
  }

  tags = local.tags
}

#---------------------------------------------------------------
# EKS Cluster using base module
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

  # managed_node_groups = var.managed_node_groups
managed_node_groups = {
  # The following Node groups are a placeholder to create Node groups for running Spark TPC-DS benchmarks
  spark_benchmark_ebs = {
    name        = "spark_benchmark_ebs"
    description = "Managed node group for Spark Benchmarks with EBS using x86 or ARM"
    # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
    subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc_blueprint.private_subnets, module.vpc_blueprint.private_subnets_cidr_blocks) :
      substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
    ]

    # Change ami_type= AL2023_x86_64_STANDARD for x86 instances
    ami_type = "AL2023_ARM_64_STANDARD" # arm64

    # Node group will be created with zero instances when you deploy the blueprint.
    # You can change the min_size and desired_size to 6 instances
    # desired_size might not be applied through terrafrom once the node group is created so this needs to be adjusted in AWS Console.
    min_size     = 0 # Change min and desired to 6 for running benchmarks
    max_size     = 8
    desired_size = 0 # Change min and desired to 6 for running benchmarks

    # This storage is used as a shuffle for non NVMe SSD instances. e.g., r8g instances
    block_device_mappings = {
      xvda = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size           = 300
          volume_type           = "gp3"
          iops                  = 3000
          encrypted             = true
          delete_on_termination = true
        }
      }
    }

    # Change the instance type as you desire and match with ami_type
    instance_types = ["r8g.12xlarge"] # Change Instance type to run the benchmark with various instance types

    labels = {
      NodeGroupType = "spark_benchmark_ebs"
    }

    tags = {
      Name          = "spark_benchmark_ebs"
      NodeGroupType = "spark_benchmark_ebs"
    }
  }

  spark_benchmark_ssd = {
    name        = "spark_benchmark_ssd"
    description = "Managed node group for Spark Benchmarks with NVMEe SSD using x86 or ARM"
    # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
    subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc_blueprint.private_subnets, module.vpc_blueprint.private_subnets_cidr_blocks) :
      substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
    ]

    ami_type = "AL2023_x86_64_STANDARD" # x86

    # Node group will be created with zero instances when you deploy the blueprint.
    # You can change the min_size and desired_size to 6 instances
    # desired_size might not be applied through terrafrom once the node group is created so this needs to be adjusted in AWS Console.
    min_size     = 0
    max_size     = 8
    desired_size = 0

    instance_types = ["c5d.12xlarge"] # c5d.12xlarge = 2 x 900 NVMe SSD

    cloudinit_pre_nodeadm = [
      {
        content_type = "application/node.eks.aws"
        content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              instance:
                localStorage:
                  strategy: RAID0
          EOT
      }
    ]

    labels = {
      NodeGroupType = "spark_benchmark_ssd"
    }

    tags = {
      Name          = "spark_benchmark_ssd"
      NodeGroupType = "spark_benchmark_ssd"
    }
  }

  spark_operator_bench = {
    name        = "spark_operator_bench"
    description = "Managed node group for Spark Operator Benchmarks with EBS using x86 or ARM"
    # Filtering only Secondary CIDR private subnets starting with "100.". Subnet IDs where the nodes/node groups will be provisioned
    subnet_ids = [element(compact([for subnet_id, cidr_block in zipmap(module.vpc_blueprint.private_subnets, module.vpc_blueprint.private_subnets_cidr_blocks) :
      substr(cidr_block, 0, 4) == "100." ? subnet_id : null]), 0)
    ]

    ami_type = "AL2023_x86_64_STANDARD"

    cloudinit_pre_nodeadm = [
      {
        content_type = "application/node.eks.aws"
        content      = <<-EOT
            ---
            apiVersion: node.eks.aws/v1alpha1
            kind: NodeConfig
            spec:
              kubelet:
                config:
                  maxPods: 220
          EOT
      }
    ]

    min_size     = 0
    max_size     = 200
    desired_size = 0

    instance_types = ["m6a.4xlarge"]

    labels = {
      NodeGroupType = "spark-operator-benchmark-ng"
    }

    taints = {
      benchmark = {
        key      = "spark-operator-benchmark-ng"
        effect   = "NO_SCHEDULE"
        operator = "EXISTS"
      }
    }

    tags = {
      Name          = "spark-operator-benchmark-ng"
      NodeGroupType = "spark-operator-benchmark-ng"
    }
  }
}
  tags = local.tags
}

# Providers are configured in versions.tf

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