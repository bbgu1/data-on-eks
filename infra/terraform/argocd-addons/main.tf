provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  partition = data.aws_partition.current.partition
  region    = data.aws_region.current.name

  # Private ECR Account IDs for EMR Spark Operator Helm Charts
  account_region_map = {
    ap-northeast-1 = "059004520145"
    ap-northeast-2 = "996579266876"
    ap-south-1     = "235914868574"
    ap-southeast-1 = "671219180197"
    ap-southeast-2 = "038297999601"
    ca-central-1   = "351826393999"
    eu-central-1   = "107292555468"
    eu-north-1     = "830386416364"
    eu-west-1      = "483788554619"
    eu-west-2      = "118780647275"
    eu-west-3      = "307523725174"
    sa-east-1      = "052806832358"
    us-east-1      = "755674844232"
    us-east-2      = "711395599931"
    us-west-1      = "608033475327"
    us-west-2      = "895885662937"
  }

  spark_history_server_name = "spark-history-server"
  spark_history_server_service_account = "spark-history-server-sa"

  # Default values using expert aws-ia pattern
  spark_history_server_default_values = <<-EOT
    logStore:
      type: "s3"
      s3:
        irsaRoleArn: "${try(module.spark_history_server_irsa[0].iam_role_arn, "")}"
    serviceAccount:
      create: true
      name: "spark-history-server-sa"
      annotations:
        eks.amazonaws.com/role-arn: "${try(module.spark_history_server_irsa[0].iam_role_arn, "")}"
    resources:
      requests:
        cpu: "100m"
        memory: "256Mi"
      limits:
        cpu: "500m"
        memory: "512Mi"
  EOT

  karpenter_default_values = <<-EOT
    controller:
      resources:
        requests:
          cpu: "1"
          memory: "1Gi"
        limits:
          cpu: "1"
          memory: "1Gi"
    nodeSelector:
      karpenter.sh/controller: "true"
    dnsPolicy: "Default"
    tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
          - matchExpressions:
            - key: karpenter.sh/controller
              operator: In
              values:
              - "true"
  EOT
}

#---------------------------------------------------------------
# IRSA for Spark History Server
#---------------------------------------------------------------
module "spark_history_server_irsa" {
  source = "../irsa"
  count  = var.enable_spark_history_server ? 1 : 0

  # IAM role for service account (IRSA)
  create_role                   = try(var.spark_history_server_helm_config.create_role, true)
  role_name                     = try(var.spark_history_server_helm_config.role_name, local.spark_history_server_name)
  role_name_use_prefix          = try(var.spark_history_server_helm_config.role_name_use_prefix, true)
  role_path                     = try(var.spark_history_server_helm_config.role_path, "/")
  role_permissions_boundary_arn = try(var.spark_history_server_helm_config.role_permissions_boundary_arn, null)
  role_description              = try(var.spark_history_server_helm_config.role_description, "IRSA for ${local.spark_history_server_name} project")

  role_policy_arns = try(var.spark_history_server_helm_config.role_policy_arns, { "S3ReadOnlyPolicy" : "arn:${local.partition}:iam::aws:policy/AmazonS3ReadOnlyAccess" })

  oidc_providers = {
    this = {
      provider_arn    = var.oidc_provider_arn
      namespace       = local.spark_history_server_name
      service_account = local.spark_history_server_service_account
    }
  }
}

# Spark History Server Application
resource "kubectl_manifest" "spark_history_server" {
  count = var.enable_spark_history_server ? 1 : 0
  
  yaml_body = templatefile("${path.module}/../../../infra/argocd-applications/spark-history-server.yaml", {
    # Expert aws-ia pattern: yamlencode(merge(yamldecode(defaults), try(user_values)))
    merged_values_yaml = yamlencode(merge(
      yamldecode(local.spark_history_server_default_values),
      try(yamldecode(var.spark_history_server_helm_config.values[0]), {})
    ))
  })
}

resource "kubectl_manifest" "karpenter" {
  count = var.enable_karpenter ? 1 : 0
  
  yaml_body = templatefile("${path.module}/../../../infra/argocd-applications/karpenter.yaml", {
    repository_username = data.aws_ecrpublic_authorization_token.token.user_name
    repository_password = data.aws_ecrpublic_authorization_token.token.password
    # Expert aws-ia pattern: yamlencode(merge(yamldecode(defaults), try(user_values)))
    merged_values_yaml = yamlencode(merge(
      yamldecode(local.karpenter_default_values),
      try(yamldecode(var.karpenter_helm_config.values[0]), {})
    ))
  })
}


# ==============================================================================
# ArgoCD Applications - Deployed via kubectl_manifest with terraform
# ==============================================================================


# # Karpenter Resources (NodePools and EC2NodeClasses) - Direct deployment
# data "kubectl_path_documents" "karpenter_resources" {
#   pattern = "${path.module}/../values/nodepool-*.yaml"
#   vars = {
#     cluster_name                     = module.eks_blueprint.cluster_name
#     karpenter_node_iam_role_name = module.eks_blueprint.karpenter_node_iam_role_name
#   }
# }

# data "kubectl_path_documents" "karpenter_nodeclasses" {
#   pattern = "${path.module}/../values/ec2nodeclass-*.yaml"
#   vars = {
#     cluster_name                     = module.eks_blueprint.cluster_name
#     karpenter_node_iam_role_name = module.eks_blueprint.karpenter_node_iam_role_name
#   }
# }

# resource "kubectl_manifest" "karpenter_nodepools" {
#   for_each  = data.kubectl_path_documents.karpenter_resources.manifests
#   yaml_body = each.value
  
#   depends_on = [kubectl_manifest.karpenter]
# }

# resource "kubectl_manifest" "karpenter_ec2nodeclasses" {
#   for_each  = data.kubectl_path_documents.karpenter_nodeclasses.manifests
#   yaml_body = each.value
  
#   depends_on = [kubectl_manifest.karpenter]
# }

# # Spark Operator Application
# resource "kubectl_manifest" "spark_operator" {
#   count = var.enable_spark_operator ? 1 : 0
  
#   yaml_body = templatefile("${path.module}/../../../infra/argocd/data/spark-operator/application.yaml", {
#     # Uses default values only
#   })

#   depends_on = [
#     module.eks_blueprint,
#     kubectl_manifest.karpenter_nodepools,
#     kubectl_manifest.karpenter_ec2nodeclasses
#   ]
# }


# # YuniKorn Scheduler Application
# resource "kubectl_manifest" "yunikorn" {
#   count = var.enable_yunikorn ? 1 : 0
  
#   yaml_body = templatefile("${path.module}/../../../infra/argocd/data/yunikorn/application.yaml", {
#     # Uses default queue configuration
#   })

#   depends_on = [module.eks_blueprint]
# }
