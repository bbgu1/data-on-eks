#---------------------------------------------------------------
# Pod Identity Roles - Modern IRSA Replacement
#---------------------------------------------------------------

#-------------------------------------------------------
# EBS CSI Driver Pod Identity Role
#-------------------------------------------------------
resource "aws_iam_role" "ebs_csi_pod_identity_role" {
  name = "${var.name}-ebs-csi-pod-identity-role"

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

  tags = var.tags
}

# Attach EBS CSI policy to the role
resource "aws_iam_role_policy_attachment" "ebs_csi_pod_identity_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_pod_identity_role.name
}

# Pod Identity Association for EBS CSI Driver
resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi_pod_identity_role.arn

  tags = var.tags
}

#-------------------------------------------------------
# S3 CSI Driver Pod Identity Role
#-------------------------------------------------------
resource "aws_iam_role" "s3_csi_pod_identity_role" {
  count = var.enable_mountpoint_s3_csi ? 1 : 0
  name  = "${var.name}-s3-csi-pod-identity-role"

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

  tags = var.tags
}

# Attach S3 CSI policy to the role
resource "aws_iam_role_policy_attachment" "s3_csi_pod_identity_policy" {
  count      = var.enable_mountpoint_s3_csi ? 1 : 0
  policy_arn = aws_iam_policy.s3_csi_access_policy[0].arn
  role       = aws_iam_role.s3_csi_pod_identity_role[0].name
}

# Pod Identity Association for S3 CSI Driver
resource "aws_eks_pod_identity_association" "s3_csi" {
  count           = var.enable_mountpoint_s3_csi ? 1 : 0
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "s3-csi-driver-sa"
  role_arn        = aws_iam_role.s3_csi_pod_identity_role[0].arn

  tags = var.tags
}

#---------------------------------------------------------------
# S3 CSI Driver Policy (used by Pod Identity)
#---------------------------------------------------------------
resource "aws_iam_policy" "s3_csi_access_policy" {
  count       = var.enable_mountpoint_s3_csi ? 1 : 0
  name        = "${var.name}-S3CSIAccess"
  path        = "/"
  description = "S3 CSI Driver Access Policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MountpointFullBucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = "*"
      },
      {
        Sid    = "MountpointFullObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:DeleteObject"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}
