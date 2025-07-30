# ==============================================================================
# ArgoCD Applications - Deployed via kubectl_manifest with terraform
# ==============================================================================

# Karpenter Application
resource "kubectl_manifest" "karpenter" {
  yaml_body = templatefile("${path.module}/../../../infra/argocd/core/karpenter/application.yaml", {
    cluster_name                     = module.eks_blueprint.cluster_name
    cluster_endpoint                 = module.eks_blueprint.cluster_endpoint
    karpenter_sqs_queue_name         = module.eks_blueprint.karpenter_sqs_queue_name
  })

  depends_on = [module.eks_blueprint]
}

# Karpenter Resources (NodePools and EC2NodeClasses) - Direct deployment
data "kubectl_path_documents" "karpenter_resources" {
  pattern = "${path.module}/../values/nodepool-*.yaml"
  vars = {
    cluster_name                     = module.eks_blueprint.cluster_name
    karpenter_node_instance_profile = module.eks_blueprint.karpenter_node_instance_profile_name
  }
}

data "kubectl_path_documents" "karpenter_nodeclasses" {
  pattern = "${path.module}/../values/ec2nodeclass-*.yaml"
  vars = {
    cluster_name                     = module.eks_blueprint.cluster_name
    karpenter_node_instance_profile = module.eks_blueprint.karpenter_node_instance_profile_name
  }
}

resource "kubectl_manifest" "karpenter_nodepools" {
  for_each  = data.kubectl_path_documents.karpenter_resources.manifests
  yaml_body = each.value
  
  depends_on = [kubectl_manifest.karpenter]
}

resource "kubectl_manifest" "karpenter_ec2nodeclasses" {
  for_each  = data.kubectl_path_documents.karpenter_nodeclasses.manifests
  yaml_body = each.value
  
  depends_on = [kubectl_manifest.karpenter]
}

# Spark Operator Application
resource "kubectl_manifest" "spark_operator" {
  count = var.enable_spark_operator ? 1 : 0
  
  yaml_body = templatefile("${path.module}/../../../infra/argocd/data/spark-operator/application.yaml", {
    # Uses default values only
  })

  depends_on = [
    module.eks_blueprint,
    kubectl_manifest.karpenter_nodepools,
    kubectl_manifest.karpenter_ec2nodeclasses
  ]
}

# Spark History Server Application
resource "kubectl_manifest" "spark_history_server" {
  count = var.enable_spark_history_server ? 1 : 0
  
  yaml_body = templatefile("${path.module}/../../../infra/argocd/data/spark-history-server/application.yaml", {
    s3_bucket_name = module.s3_bucket.s3_bucket_id
    shs_role_arn   = ""
    s3_event_log_path = "spark-events/"
  })

  depends_on = [module.eks_blueprint]
}

# YuniKorn Scheduler Application
resource "kubectl_manifest" "yunikorn" {
  count = var.enable_yunikorn ? 1 : 0
  
  yaml_body = templatefile("${path.module}/../../../infra/argocd/data/yunikorn/application.yaml", {
    # Uses default queue configuration
  })

  depends_on = [module.eks_blueprint]
}
