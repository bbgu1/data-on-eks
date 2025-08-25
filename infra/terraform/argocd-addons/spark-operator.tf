locals {
  spark_operator_name            = "spark-operator"
  spark_operator_service_account = "spark-operator-sa"

  # Default Spark Operator configuration
  spark_operator_default_values = yamldecode(<<-EOT
    controller:
      # -- Number of replicas of controller.
      replicas: 1
      # -- Reconcile concurrency, higher values might increase memory usage.
      # -- Increased from 10 to 20 to leverage more cores from the instance
      workers: 20
    batchScheduler:
      # -- Enable batch scheduler support
      enable: false
      # -- Default batch scheduler (will be overridden by user values)
      default: "yunikorn"
    #   -- Uncomment this for Spark Operator scale test
    #   -- Spark Operator is CPU bound so add more CPU or use compute optimized instance for handling large number of job submissions
    #   nodeSelector:
    #     NodeGroupType: spark-operator-benchmark
    #   resources:
    #     requests:
    #       cpu: 33000m
    #       memory: 50Gi
    # webhook:
    #   nodeSelector:
    #     NodeGroupType: spark-operator-benchmark
    #   resources:
    #     requests:
    #       cpu: 1000m
    #       memory: 10Gi
    spark:
      # -- List of namespaces where to run spark jobs.
      # If empty string is included, all namespaces will be allowed.
      jobNamespaces:
        - ""
      serviceAccount:
        # -- Specifies whether to create a service account for spark applications.
        create: false
      rbac:
        # -- Specifies whether to create RBAC resources for spark applications.
        create: false
    prometheus:
      metrics:
        enable: true
        port: 8080
        portName: metrics
        endpoint: /metrics
        prefix: ""
      # Prometheus pod monitor for controller pods
      # Note: The kube-prometheus-stack addon must deploy before the PodMonitor CRD is available.
      #       This can cause the terraform apply to fail since the addons are deployed in parallel
      podMonitor:
        # -- Specifies whether to create pod monitor.
        create: false
        labels: {}
        # -- The label to use to retrieve the job name from
        jobLabel: spark-operator-podmonitor
        # -- Prometheus metrics endpoint properties. `metrics.portName` will be used as a port
        podMetricsEndpoint:
          scheme: http
          interval: 5s
  EOT
  )

  # Parse user values (or empty map)
  spark_operator_user = try(yamldecode(try(var.spark_operator_helm_config.values[0], "")), {})

  # Merge default values with user values, giving precedence to user values
  spark_operator_values_map = merge(local.spark_operator_default_values, local.spark_operator_user)
}

#---------------------------------------------------------------
# Spark Operator Application
#---------------------------------------------------------------
resource "kubectl_manifest" "spark_operator" {
  count = var.enable_spark_operator ? 1 : 0

  yaml_body = templatefile("${path.module}/../../../infra/argocd-applications/spark-operator.yaml", {
    user_values_yaml = indent(8, yamlencode(local.spark_operator_values_map))
  })
}

