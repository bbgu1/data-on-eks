# Teams Module

This Terraform module creates reusable team configurations with Pod Identity for EKS clusters. It's designed to eliminate code duplication across Data-on-EKS blueprints by providing a standardized way to create IAM roles, Pod Identity associations, and team resources.

## Features

- **Pod Identity Integration**: Uses AWS EKS Pod Identity instead of IRSA for simpler configuration
- **Flexible Policy Attachment**: Support for multiple IAM policies per team
- **Reusable**: Can be used across different blueprint types (Spark, Flink, Argo, etc.)
- **Secure**: Follows least-privilege security principles

## Usage

### Basic Usage

```hcl
module "spark_teams" {
  source = "../../../infra/terraform/teams"

  cluster_name = module.eks.cluster_name
  name_prefix  = "my-cluster"

  teams = {
    team-a = {
      name                = "team-a"
      namespace           = "team-a"
      service_account     = "default"
      iam_policy_arns     = [aws_iam_policy.my_policy.arn]
      additional_policies = {}
      tags = {
        Team = "team-a"
      }
    }
  }

  tags = {
    Environment = "dev"
    Blueprint   = "my-blueprint"
  }
}
```

### Advanced Usage with Multiple Policies

```hcl
module "spark_teams" {
  source = "../../../infra/terraform/teams"

  cluster_name = module.eks.cluster_name
  name_prefix  = "spark-cluster"

  teams = {
    spark-team-a = {
      name            = "spark-team-a"
      namespace       = "spark-team-a"
      service_account = "spark"
      iam_policy_arns = [
        aws_iam_policy.spark_base.arn,
        aws_iam_policy.cloudwatch_logs.arn
      ]
      additional_policies = {
        s3_extra = aws_iam_policy.team_a_s3_extra.arn
        ecr      = aws_iam_policy.ecr_access.arn
      }
      tags = {
        Team        = "spark-team-a"
        Environment = "production"
      }
    }
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| teams | Map of team configurations | `map(object)` | n/a | yes |
| cluster_name | Name of the EKS cluster | `string` | n/a | yes |
| name_prefix | Prefix for resource names | `string` | `"data-on-eks"` | no |
| tags | A map of tags to assign to resources | `map(string)` | `{}` | no |

### Team Object Structure

```hcl
{
  name                = string           # Team name (used for role naming)
  namespace           = string           # Kubernetes namespace
  service_account     = string           # Kubernetes service account name
  iam_policy_arns     = list(string)     # List of IAM policy ARNs to attach
  additional_policies = map(string)      # Optional additional policies
  tags               = map(string)       # Optional team-specific tags
}
```

## Outputs

| Name | Description |
|------|-------------|
| team_roles | Map of team names to IAM role ARNs |
| team_role_names | Map of team names to IAM role names |
| pod_identity_associations | Map of team names to Pod Identity association details |
| team_configs | Original team configurations with role ARNs |

## Integration with Blueprints

### 1. Blueprint creates IAM policies

Blueprints are responsible for creating workload-specific IAM policies:

```hcl
# In spark-on-eks blueprint
resource "aws_iam_policy" "spark_jobs" {
  name_prefix = "${local.name}-spark-jobs"
  policy      = data.aws_iam_policy_document.spark_jobs.json
}

data "aws_iam_policy_document" "spark_jobs" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.spark.arn}/*"]
  }
}
```

### 2. Blueprint calls teams module

```hcl
module "teams" {
  source = "../../../infra/terraform/teams"
  
  cluster_name = module.eks.cluster_name
  teams = {
    my-team = {
      name                = "my-team"
      namespace           = "my-team"
      service_account     = "default"
      iam_policy_arns     = [aws_iam_policy.spark_jobs.arn]
    }
  }
}
```

### 3. Kubernetes resources managed separately

Use ArgoCD or direct Kubernetes resources to create namespaces, service accounts, and RBAC:

```hcl
# Option 1: Direct Kubernetes resources
resource "kubernetes_namespace" "teams" {
  for_each = module.teams.team_configs
  metadata {
    name = each.value.namespace
  }
}

# Option 2: ArgoCD Application (recommended)
resource "kubectl_manifest" "teams_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    # ... ArgoCD configuration
  })
}
```

## Comparison with Old Pattern

### Before (IRSA with eks-blueprints-addon)

```hcl
# Duplicated across every blueprint
module "spark_team_irsa" {
  for_each = toset(local.teams)
  source   = "aws-ia/eks-blueprints-addon/aws"
  
  create_release = false
  create_role    = true
  role_name      = "${local.name}-${each.value}"
  
  oidc_providers = {
    this = {
      provider_arn    = module.eks.oidc_provider_arn
      namespace       = each.value
      service_account = each.value
    }
  }
}
```

### After (Pod Identity with teams module)

```hcl
# Reusable across all blueprints
module "teams" {
  source = "../../../infra/terraform/teams"
  
  cluster_name = module.eks.cluster_name
  teams = var.teams  # Defined once, reused everywhere
}
```

## Benefits

1. **70% code reduction**: Eliminates duplicate team management code
2. **Pod Identity native**: Simpler authentication without OIDC complexity
3. **Consistent**: Standardized team patterns across all blueprints
4. **Flexible**: Easy to add new teams or modify existing ones
5. **Maintainable**: Centralized upgrades and bug fixes

## Examples

See the `blueprints/spark-on-eks/terraform/teams.tf` file for a complete example of how this module is integrated into a blueprint.

## Requirements

- Terraform >= 1.0
- AWS Provider >= 5.0
- EKS cluster with Pod Identity add-on enabled

## License

This module is part of the Data-on-EKS project and follows the same license terms.