#---------------------------------------------------------------
# Spark Operator Pod Identity
#---------------------------------------------------------------

# IAM Policy for Spark Operator
data "aws_iam_policy_document" "spark_operator" {
  statement {
    sid       = "S3Access"
    effect    = "Allow"
    resources = ["arn:${data.aws_partition.current.partition}:s3:::*"]

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

resource "aws_iam_policy" "spark_operator" {
  name_prefix = "${local.name}-spark-operator"
  path        = "/"
  description = "IAM policy for Spark Operator"
  policy      = data.aws_iam_policy_document.spark_operator.json
  tags        = local.tags
}

# IAM Role for Spark Operator Pod Identity
resource "aws_iam_role" "spark_operator" {
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

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "spark_operator" {
  role       = aws_iam_role.spark_operator.name
  policy_arn = aws_iam_policy.spark_operator.arn
}

# Pod Identity Association for Spark Operator
resource "aws_eks_pod_identity_association" "spark_operator" {
  cluster_name    = module.eks.cluster_name
  namespace       = "spark-operator"
  service_account = "spark-operator"
  role_arn        = aws_iam_role.spark_operator.arn

  tags = local.tags
}

#---------------------------------------------------------------
# Spark Jobs Pod Identity (for Spark Applications)
#---------------------------------------------------------------

# IAM Policy for Spark Jobs
data "aws_iam_policy_document" "spark_jobs" {
  statement {
    sid       = "S3Access"
    effect    = "Allow"
    resources = [
      aws_s3_bucket.spark.arn,
      "${aws_s3_bucket.spark.arn}/*"
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

# IAM Role for Spark Jobs Pod Identity  
resource "aws_iam_role" "spark_jobs" {
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

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "spark_jobs" {
  role       = aws_iam_role.spark_jobs.name
  policy_arn = aws_iam_policy.spark_jobs.arn
}

# Pod Identity Associations for Spark Jobs in different namespaces
resource "aws_eks_pod_identity_association" "spark_jobs" {
  for_each = toset([
    "spark-team-a",
    "spark-team-b", 
    "spark-team-c",
    "default"
  ])

  cluster_name    = module.eks.cluster_name
  namespace       = each.value
  service_account = "spark"
  role_arn        = aws_iam_role.spark_jobs.arn

  tags = local.tags
  
  depends_on = [kubernetes_namespace.spark_teams]
}

#---------------------------------------------------------------
# Spark History Server Service Account
#---------------------------------------------------------------
resource "kubernetes_service_account" "spark_history_server" {
  metadata {
    name      = "spark-history-server"
    namespace = "spark-operator"
    
    annotations = {
      "eks.amazonaws.com/pod-identity-association" = "spark-operator"
    }
    
    labels = {
      "app.kubernetes.io/name"      = "spark-history-server"
      "app.kubernetes.io/part-of"   = "spark-on-eks"
    }
  }

  depends_on = [module.eks]
}

#---------------------------------------------------------------
# Spark Job Service Accounts
#---------------------------------------------------------------
resource "kubernetes_service_account" "spark_jobs" {
  for_each = toset([
    "spark-team-a",
    "spark-team-b",
    "spark-team-c", 
    "default"
  ])

  metadata {
    name      = "spark"
    namespace = each.value
    
    annotations = {
      "eks.amazonaws.com/pod-identity-association" = "spark-jobs"
    }
    
    labels = {
      "app.kubernetes.io/name"      = "spark"
      "app.kubernetes.io/part-of"   = "spark-on-eks"
      "team"                        = each.value
    }
  }

  depends_on = [kubernetes_namespace.spark_teams]
}