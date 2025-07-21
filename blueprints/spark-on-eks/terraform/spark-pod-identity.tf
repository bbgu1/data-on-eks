#---------------------------------------------------------------
# Spark Operator Pod Identity - Blueprint Specific
#---------------------------------------------------------------

# Spark Operator Pod Identity Role
resource "aws_iam_role" "spark_operator_pod_identity_role" {
  name = "${local.name}-spark-operator-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  managed_policy_arns = [aws_iam_policy.spark_operator_policy.arn]
  tags = local.tags
}

# Pod Identity Association for Spark Operator
resource "aws_eks_pod_identity_association" "spark_operator" {
  cluster_name    = module.eks_blueprint.cluster_name
  namespace       = "spark-operator"
  service_account = "spark-operator"
  role_arn        = aws_iam_role.spark_operator_pod_identity_role.arn

  tags = local.tags
}

# Pod Identity Associations for Spark Jobs (Multiple Namespaces)
resource "aws_eks_pod_identity_association" "spark_jobs" {
  for_each = toset([
    "default",
    "spark-team-a", 
    "spark-team-b",
    "spark-team-c"
  ])

  cluster_name    = module.eks_blueprint.cluster_name
  namespace       = each.value
  service_account = "spark"
  role_arn        = aws_iam_role.spark_jobs_pod_identity_role.arn

  tags = local.tags
}

# Spark Jobs Pod Identity Role (for actual Spark applications)
resource "aws_iam_role" "spark_jobs_pod_identity_role" {
  name = "${local.name}-spark-jobs-pod-identity-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  managed_policy_arns = [aws_iam_policy.spark_jobs_policy.arn]
  tags = local.tags
}

#---------------------------------------------------------------
# Spark-Specific IAM Policies
#---------------------------------------------------------------

# Spark Operator Policy (manages Spark applications)
resource "aws_iam_policy" "spark_operator_policy" {
  name_prefix = "${local.name}-spark-operator"
  description = "Spark Operator policy for ${local.name}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SparkOperatorKubernetesAPI"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = module.eks_blueprint.cluster_arn
      },
      {
        Sid    = "SparkOperatorS3Access"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn,
          "arn:aws:s3:::${local.name}-*"
        ]
      },
      {
        Sid    = "SparkOperatorS3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "${module.s3_bucket.s3_bucket_arn}/*",
          "arn:aws:s3:::${local.name}-*/*"
        ]
      }
    ]
  })

  tags = local.tags
}

# Spark Jobs Policy (for actual Spark workloads)
resource "aws_iam_policy" "spark_jobs_policy" {
  name_prefix = "${local.name}-spark-jobs"
  description = "Spark Jobs execution policy for ${local.name}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SparkS3DataAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn,
          "${module.s3_bucket.s3_bucket_arn}/*",
          "arn:aws:s3:::${local.name}-*",
          "arn:aws:s3:::${local.name}-*/*"
        ]
      },
      {
        Sid    = "SparkCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/spark/*"
      },
      {
        Sid    = "SparkGlueDataCatalog"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases", 
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchCreatePartition",
          "glue:BatchDeletePartition",
          "glue:BatchUpdatePartition"
        ]
        Resource = [
          "arn:aws:glue:${local.region}:${local.account_id}:catalog",
          "arn:aws:glue:${local.region}:${local.account_id}:database/*",
          "arn:aws:glue:${local.region}:${local.account_id}:table/*"
        ]
      }
    ]
  })

  tags = local.tags
}