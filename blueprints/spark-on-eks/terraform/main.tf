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
  name = module.eks.cluster_name
}

#---------------------------------------------------------------
# VPC using base module
#---------------------------------------------------------------
module "vpc" {
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
module "eks" {
  source = "../../../infra/terraform/eks"

  name                           = local.name
  eks_cluster_version            = var.eks_cluster_version
  cluster_endpoint_public_access = var.cluster_endpoint_public_access

  vpc_id                      = module.vpc.vpc_id
  private_subnets             = module.vpc.private_subnets
  private_subnets_cidr_blocks = module.vpc.private_subnets_cidr_blocks

  kms_key_admin_roles = var.kms_key_admin_roles

  tags = local.tags
}

#---------------------------------------------------------------
# S3 bucket for Spark Event Logs
#---------------------------------------------------------------
resource "aws_s3_bucket" "spark" {
  bucket_prefix = "${local.name}-spark-logs-"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "spark" {
  bucket = aws_s3_bucket.spark.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "spark" {
  bucket = aws_s3_bucket.spark.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Creating an s3 bucket prefix for Spark History event logs
resource "aws_s3_object" "spark_event_logs" {
  bucket       = aws_s3_bucket.spark.id
  key          = "spark-event-logs/"
  content_type = "application/x-directory"
  
  depends_on = [aws_s3_bucket.spark]
}

#---------------------------------------------------------------
# GP3 Encrypted Storage Class for better performance
#---------------------------------------------------------------
resource "kubernetes_annotations" "gp2_default" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }
  force = true

  depends_on = [module.eks]
}

resource "kubernetes_storage_class" "ebs_csi_encrypted_gp3_storage_class" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "xfs"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.gp2_default]
}

#---------------------------------------------------------------
# Karpenter Access Entry for Node IAM Role
#---------------------------------------------------------------
resource "aws_eks_access_entry" "karpenter_nodes" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.eks.karpenter_node_iam_role_arn
  type          = "EC2_LINUX"
}

#---------------------------------------------------------------
# Grafana Admin Password Secret
#---------------------------------------------------------------
resource "random_password" "grafana" {
  length           = 16
  special          = true
  override_special = "@_"
}

resource "aws_secretsmanager_secret" "grafana" {
  name                    = "${local.name}-grafana"
  recovery_window_in_days = 0 # Set to zero for this example to force delete during Terraform destroy
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "grafana" {
  secret_id     = aws_secretsmanager_secret.grafana.id
  secret_string = random_password.grafana.result
}

#---------------------------------------------------------------
# Data on EKS Kubernetes Addons (for backward compatibility)
#---------------------------------------------------------------
# We include a minimal configuration here for teams that may depend on this module
# The main addons are now managed via ArgoCD
module "eks_data_addons" {
  source  = "aws-ia/eks-data-addons/aws"
  version = "~> 1.37"

  oidc_provider_arn = module.eks.oidc_provider_arn

  # Essential addons only - ArgoCD will manage the rest
  enable_karpenter           = true
  enable_spark_operator      = false # Managed by ArgoCD
  enable_spark_history_server = false # Managed by ArgoCD
  enable_yunikorn            = false # Managed by ArgoCD

  # Karpenter configuration
  karpenter_helm_config = {
    timeout = "300"
    values = [
      <<-EOT
        nodeClassRef:
          apiVersion: karpenter.k8s.aws/v1beta1
          kind: EC2NodeClass
          name: karpenter-nodeclass
        
        controller:
          resources:
            requests:
              cpu: 1
              memory: 1Gi
            limits:
              cpu: 1
              memory: 1Gi
      EOT
    ]
  }
}

#---------------------------------------------------------------
# EKS Blueprints Addons (Core Infrastructure)
#---------------------------------------------------------------
module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.20"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # EKS Managed Addons
  eks_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
    
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.eks.ebs_csi_iam_role_arn
    }
    
    aws-s3-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.eks.s3_csi_iam_role_arn
    }
  }

  # AWS Load Balancer Controller
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    service_account_role_arn = module.eks.aws_load_balancer_controller_iam_role_arn
  }

  # CoreDNS addon configuration
  enable_coredns_cluster_proportional_autoscaler = true

  # Ingress controllers
  enable_ingress_nginx = true

  # ArgoCD for GitOps
  enable_argocd = true
  argocd = {
    values = [
      <<-EOT
        configs:
          cm:
            application.instanceLabelKey: argocd.argoproj.io/instance
            server.rbac.log.enforce.enable: false
            exec.enabled: true
            admin.enabled: true
            timeout.reconciliation: 300s
            oidc.config: ""
            
          params:
            application.namespaces: "*"
            server.insecure: true
            
        dex:
          enabled: false
          
        server:
          service:
            type: ClusterIP
          
          ingress:
            enabled: true
            ingressClassName: nginx
            annotations:
              nginx.ingress.kubernetes.io/rewrite-target: /
              nginx.ingress.kubernetes.io/backend-protocol: HTTP
            hosts:
              - argocd.${local.name}.local
      EOT
    ]
  }

  tags = local.tags
}

#---------------------------------------------------------------
# Create Spark team namespaces
#---------------------------------------------------------------
resource "kubernetes_namespace" "spark_teams" {
  for_each = toset(["spark-team-a", "spark-team-b", "spark-team-c"])
  
  metadata {
    name = each.value
    
    labels = {
      "app.kubernetes.io/name"      = each.value
      "app.kubernetes.io/part-of"   = "spark-on-eks"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
  }

  depends_on = [module.eks]
}