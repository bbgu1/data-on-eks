# Remote state configuration
# Uncomment and configure for production use

# terraform {
#   backend "s3" {
#     bucket         = "your-terraform-state-bucket"
#     key            = "data-on-eks/spark-k8s-operator/terraform.tfstate"
#     region         = "us-west-2"
#     encrypt        = true
#     dynamodb_table = "your-terraform-lock-table"
#     
#     # Optional: Use assume role for cross-account access
#     # assume_role = {
#     #   role_arn = "arn:aws:iam::ACCOUNT:role/TerraformRole"
#     # }
#   }
# }