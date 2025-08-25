locals {
  spark_history_server_name            = "spark-history-server"
  spark_history_server_service_account = "spark-history-server-sa"

  # Parse user values (or empty map)
  shs_user = try(yamldecode(try(var.spark_history_server_helm_config.values[0], "")), {})

  # If user didn't set irsaRoleArn, add it
  shs_with_irsa = merge(
    local.shs_user,
    {
      logStore = merge(
        try(local.shs_user.logStore, {}),
        {
          type = "s3"
          s3 = merge(
            try(local.shs_user.logStore.s3, {}),
            { irsaRoleArn = try(module.spark_history_server_irsa[0].iam_role_arn, null) }
          )
        }
      )
    }
  )

  spark_history_server_values_map = local.shs_with_irsa
}

#---------------------------------------------------------------
# Spark History Server Application
#---------------------------------------------------------------
resource "kubectl_manifest" "spark_history_server" {
  count = var.enable_spark_history_server ? 1 : 0

  yaml_body = templatefile("${path.module}/../../../infra/argocd-applications/spark-history-server.yaml", {
    # Place under `helm.valuesObject:` at 8 spaces (adjust if your template indent differs)
    user_values_yaml = indent(8, yamlencode(local.spark_history_server_values_map))
  })
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
