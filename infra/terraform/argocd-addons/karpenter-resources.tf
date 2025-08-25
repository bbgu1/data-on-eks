#---------------------------------------------------------------
# Karpenter Resources (NodePools and EC2NodeClasses)
# Hardcoded manifests deployed directly via Terraform
#---------------------------------------------------------------

# Deploy Karpenter Resources directly (not via ArgoCD)
# This is a special case - other addons use ArgoCD, but Karpenter Resources are infrastructure
locals {
  karpenter_resources = var.enable_karpenter_resources ? {
    for f in fileset("${path.module}/../../../infra/karpenter-resources", "*.yaml") :
    f => templatefile("${path.module}/../../../infra/karpenter-resources/${f}", {
      CLUSTER_NAME                  = var.cluster_name
      KARPENTER_NODE_IAM_ROLE_NAME = var.karpenter_node_iam_role_name
    })
  } : {}
}

resource "kubectl_manifest" "karpenter_resources" {
  for_each = local.karpenter_resources
  
  yaml_body = each.value
  
  depends_on = [
    # Wait for Karpenter controller to be ready
    # Assumes Karpenter is deployed via the EKS module
  ]
}