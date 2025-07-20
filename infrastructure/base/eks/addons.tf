#---------------------------------------
# Amazon EKS Managed Add-ons
#---------------------------------------
resource "aws_eks_addon" "coredns" {
  cluster_name = module.eks.cluster_name
  addon_name   = "coredns"
  
  depends_on = [module.eks.eks_managed_node_groups]
}

resource "aws_eks_addon" "eks_pod_identity_agent" {
  cluster_name = module.eks.cluster_name
  addon_name   = "eks-pod-identity-agent"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "vpc-cni"
  preserve                 = true
  most_recent              = true
  
  configuration_values = jsonencode({
    env = {
      # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })

  depends_on = [module.eks.eks_managed_node_groups]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = module.eks.cluster_name
  addon_name   = "kube-proxy"
  
  depends_on = [module.eks.eks_managed_node_groups]
}

resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
  most_recent              = true
  
  depends_on = [module.eks.eks_managed_node_groups]
}

resource "aws_eks_addon" "aws_mountpoint_s3_csi_driver" {
  count        = var.enable_mountpoint_s3_csi ? 1 : 0
  cluster_name = module.eks.cluster_name
  addon_name   = "aws-mountpoint-s3-csi-driver"
  service_account_role_arn = var.enable_mountpoint_s3_csi ? module.s3_csi_driver_irsa[0].iam_role_arn : null
  
  depends_on = [module.eks.eks_managed_node_groups]
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name = module.eks.cluster_name
  addon_name   = "metrics-server"
  
  depends_on = [module.eks.eks_managed_node_groups]
}

resource "aws_eks_addon" "amazon_cloudwatch_observability" {
  count        = var.enable_cloudwatch_observability ? 1 : 0
  cluster_name = module.eks.cluster_name
  addon_name   = "amazon-cloudwatch-observability"
  preserve     = true
  service_account_role_arn = var.enable_cloudwatch_observability ? aws_iam_role.cloudwatch_observability_role[0].arn : null
  
  depends_on = [module.eks.eks_managed_node_groups]
}

#---------------------------------------------------------------
# GP3 Encrypted Storage Class
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
# ArgoCD Installation via Terraform
#---------------------------------------------------------------
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
  
  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  count      = var.enable_argocd ? 1 : 0
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    <<-EOT
    global:
      domain: ${var.argocd_domain}
    
    configs:
      params:
        server.insecure: true
        server.disable.auth: false
    
    server:
      service:
        type: ${var.argocd_service_type}
      
      ingress:
        enabled: ${var.argocd_ingress_enabled}
        ingressClassName: nginx
        hosts:
          - ${var.argocd_domain}
        tls:
          - secretName: argocd-server-tls
            hosts:
              - ${var.argocd_domain}
    
    dex:
      enabled: false
    
    notifications:
      enabled: false
    
    applicationSet:
      enabled: true
    EOT
  ]

  depends_on = [kubernetes_namespace.argocd]
}