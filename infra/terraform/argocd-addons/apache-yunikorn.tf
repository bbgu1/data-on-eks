locals {
  yunikorn_name = "yunikorn"

  # YuniKorn configuration - only overriding defaults where needed
  yunikorn_default_values = yamldecode(<<-EOT
    # YuniKorn configuration overrides
    yunikornDefaults:
      # The default volume bind timeout value of 10 seconds may be too short for EBS
      service.volumeBindTimeout: "60s"
      service.placeholderImage: registry.k8s.io/pause:3.7
      service.operatorPlugins: "general,spark-k8s-operator"
      admissionController.filtering.bypassNamespaces: "^kube-system$"
      # Use this configuration to configure absolute capacities for yunikorn queues
      # The Default partition uses BinPacking on Nodes by default
      queues.yaml: |
        partitions:
          - name: default
            nodesortpolicy:
              type: binpacking
            queues:
              - name: root
                submitacl: '*'
                queues:
                  - name: default
                    resources:
                      guaranteed:
                        memory: 500G
                        vcore: 50
                      max:
                        memory: 1000G
                        vcore: 100
                  - name: spark
                    resources:
                      guaranteed:
                        memory: 4000G
                        vcore: 400
                      max:
                        memory: 8000G
                        vcore: 800
                    queues:
                      - name: spark-team-a
                        resources:
                          guaranteed:
                            memory: 1000G
                            vcore: 100
                          max:
                            memory: 2000G
                            vcore: 200
                      - name: spark-team-b
                        resources:
                          guaranteed:
                            memory: 1000G
                            vcore: 100
                          max:
                            memory: 2000G
                            vcore: 200
                      - name: spark-team-c
                        resources:
                          guaranteed:
                            memory: 1000G
                            vcore: 100
                          max:
                            memory: 2000G
                            vcore: 200
                      - name: spark-s3-express
                        resources:
                          guaranteed:
                            memory: 1000G
                            vcore: 100
                          max:
                            memory: 2000G
                            vcore: 200
                  - name: prod
                    resources:
                      guaranteed:
                        memory: 1000G
                        vcore: 100
                      max:
                        memory: 2000G
                        vcore: 200
                  - name: test
                    resources:
                      guaranteed:
                        memory: 500G
                        vcore: 50
                      max:
                        memory: 1000G
                        vcore: 100
                  - name: dev
                    resources:
                      guaranteed:
                        memory: 200G
                        vcore: 20
                      max:
                        memory: 500G
                        vcore: 50
  EOT
  )

  # Parse user values (or empty map)
  yunikorn_user = try(yamldecode(try(var.yunikorn_helm_config.values[0], "")), {})

  # Merge default values with user values, giving precedence to user values
  yunikorn_values_map = merge(local.yunikorn_default_values, local.yunikorn_user)
}

#---------------------------------------------------------------
# Apache YuniKorn Scheduler Application
#---------------------------------------------------------------
resource "kubectl_manifest" "yunikorn" {
  count = var.enable_yunikorn ? 1 : 0

  yaml_body = templatefile("${path.module}/../../../infra/argocd-applications/apache-yunikorn.yaml", {
    # Place under `helm.valuesObject:` at 8 spaces (adjust if your template indent differs)
    user_values_yaml = indent(8, yamlencode(local.yunikorn_values_map))
  })
}