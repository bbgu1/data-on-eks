#---------------------------------------------------------------
# S3 bucket for Spark Event Logs and Example Data
#---------------------------------------------------------------
#tfsec:ignore:*
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

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

# Creating an s3 bucket prefix. Ensure you copy Spark History event logs under this path to visualize the dags
resource "aws_s3_object" "this" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "spark-event-logs/"
  content_type = "application/x-directory"
}

#---------------------------------------------------------------
# Spark Teams using Teams Module with Pod Identity
#---------------------------------------------------------------

# Call the teams module for Spark teams
module "spark_teams" {
  source = "../../../infra/terraform/teams"

  cluster_name = module.eks_blueprint.cluster_name
  name_prefix  = local.name

  teams = {
    spark-team-a = {
      name                = "spark-team-a"
      namespace           = "spark-team-a"
      service_account     = "spark"
      iam_policy_arns     = [aws_iam_policy.spark_jobs.arn]
      additional_policies = {}
      tags = merge(local.tags, {
        Team = "spark-team-a"
      })
    }
    spark-team-b = {
      name                = "spark-team-b"
      namespace           = "spark-team-b"
      service_account     = "spark"
      iam_policy_arns     = [aws_iam_policy.spark_jobs.arn]
      additional_policies = {}
      tags = merge(local.tags, {
        Team = "spark-team-b"
      })
    }
  }

  tags = local.tags

  depends_on = [module.eks_blueprint]
}

#---------------------------------------------------------------
# ArgoCD Application for Teams Kubernetes Resources
#---------------------------------------------------------------

# Create ArgoCD Application that deploys team namespaces, service accounts, and RBAC
resource "kubectl_manifest" "spark_teams_argocd_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "spark-teams"
      namespace = "argocd"
      labels = {
        "app.kubernetes.io/name"      = "spark-teams"
        "app.kubernetes.io/part-of"   = "spark-on-eks"
        "app.kubernetes.io/component" = "teams"
      }
    }
    spec = {
      project = "default"
      source = {
        # For local development/testing - ArgoCD uses local filesystem
        # Using local Gitea repository for development
        repoURL        = "http://gitea-http.gitea.svc.cluster.local:3000/gitea_admin/data-on-eks.git"
        targetRevision = "HEAD"
        path           = "infra/argocd/teams"
        helm = {
          valueFiles = ["values.yaml"]
          values = yamlencode({
            # Pass team configurations from Terraform to ArgoCD
            teams = [
              for team_name, team_config in module.spark_teams.team_configs : {
                name            = team_config.name
                namespace       = team_config.namespace
                serviceAccount  = team_config.service_account
                roleArn         = team_config.role_arn
                workloadType    = "spark"
                resourceQuota = {
                  "requests.cpu"              = "50"
                  "requests.memory"           = "100Gi"
                  "limits.cpu"                = "100"
                  "limits.memory"             = "200Gi"
                  "pods"                      = "50"
                  "services"                  = "5"
                  "persistentvolumeclaims"    = "5"
                }
              }
            ]
          })
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
          "RespectIgnoreDifferences=true"
        ]
        retry = {
          limit = 5
          backoff = {
            duration    = "5s"
            factor      = 2
            maxDuration = "3m"
          }
        }
      }
    }
  })

  depends_on = [module.spark_teams]
}

#---------------------------------------------------------------
# Spark Jobs Pod Identity (for Spark Applications)  
# NOTE: Team-specific roles are now managed by the teams module
#---------------------------------------------------------------

# IAM Policy for Spark Jobs (used by teams module)
data "aws_iam_policy_document" "spark_jobs" {
  statement {
    sid       = "S3Access"
    effect    = "Allow"
    resources = [
      module.s3_bucket.s3_bucket_arn,
      "${module.s3_bucket.s3_bucket_arn}/*"
    ]

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

  statement {
    sid       = "ECRAccess"
    effect    = "Allow"
    resources = ["*"]

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetAuthorizationToken",
    ]
  }
}

resource "aws_iam_policy" "spark_jobs" {
  name_prefix = "${local.name}-spark-jobs"
  path        = "/"
  description = "IAM policy for Spark job execution"
  policy      = data.aws_iam_policy_document.spark_jobs.json
  tags        = local.tags
}
