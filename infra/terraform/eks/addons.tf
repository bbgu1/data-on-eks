
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
# Gitea Installation via Terraform (Local Git Server)
#---------------------------------------------------------------
resource "random_password" "gitea_admin_password" {
  length  = 16
  special = true
  upper   = true
  lower   = true
  numeric = true
}

resource "kubernetes_secret" "gitea_admin_secret" {
  metadata {
    name      = "gitea-admin-secret"
    namespace = "gitea"
  }

  data = {
    username = "gitea_admin"
    password = random_password.gitea_admin_password.result
    email    = "admin@admin.admin"
  }

  depends_on = [module.eks.eks_cluster_id]
}

resource "helm_release" "gitea" {
  name             = "gitea"
  repository       = "https://dl.gitea.com/charts/"
  chart            = "gitea"
  version          = "12.1.1"
  timeout          = 180
  namespace        = "gitea"
  create_namespace = true

  values = [
    <<-EOT
    gitea:
      admin:
        # For production, consider using a Kubernetes secret for credentials
        username: gitea_admin
        password: "${random_password.gitea_admin_password.result}"
        email: "admin@admin.admin"
      
      config:
        # Disable password expiration
        security:
          PASSWORD_COMPLEXITY: "off"
          DISABLE_PASSWORD_COMPLEXITY_CHECK: true
          PASSWORD_EXPIRATION_DAYS: -1  # Password will not expire
        
        # Recommended cache settings for better performance
        cache:
          ADAPTER: memory

    # Single replica as HA is not required
    replicaCount: 1

    valkey-cluster:
      enabled: false

    persistence:
      enabled: true
      size: 30Gi

    postgresql-ha:
      enabled: false

    postgresql:
      enabled: true  # Use the built-in PostgreSQL
      global:
        postgresql:
          auth:
            username: gitea
            database: gitea
      primary:
        persistence:
          enabled: true
          size: 10Gi
        resources:
          requests:
            cpu: 1000m
            memory: 1024Mi

    ingress:
      enabled: false

    service:
      http:
        type: ClusterIP
        port: 3000
      ssh:
        type: ClusterIP
        port: 22

    EOT
  ]

  depends_on = [
    module.eks.eks_cluster_id,
    kubernetes_storage_class.ebs_csi_encrypted_gp3_storage_class,
    kubernetes_secret.gitea_admin_secret
  ]
}

#---------------------------------------------------------------
# ArgoCD Installation via Terraform
#---------------------------------------------------------------
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "8.1.1"
  namespace        = "argocd"
  create_namespace = true

  values = [
    <<-EOT
    configs:
      cm:
        kustomize.buildOptions: --enable-helm
        application.resourceTrackingMethod: annotation

    dex:
      enabled: false

    notifications:
      enabled: false

    EOT
  ]

  depends_on = [module.eks.eks_cluster_id]
}
