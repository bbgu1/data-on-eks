# Data-on-EKS Blueprint Architecture Guide

## Overview
This document serves as the **guiding principles** for creating, updating, and maintaining blueprints in the Data-on-EKS repository. All contributors and users must follow these architectural patterns to ensure consistency, maintainability, and standardization across the platform.

## Architecture Principles

### 🎯 Core Design Philosophy
1. **Separation of Concerns**: AWS infrastructure (Terraform) is completely separated from Kubernetes resources (ArgoCD)
2. **DRY (Don't Repeat Yourself)**: Eliminate code duplication through reusable base modules
3. **GitOps-First**: All Kubernetes workloads managed declaratively via ArgoCD
4. **Production-Ready**: Built for enterprise adoption with security, monitoring, and operational best practices

## New Folder Structure

```
data-on-eks/
├── blueprints/                         # Blueprint implementations
│   ├── datahub-on-eks/
│   ├── emr-on-eks/
│   ├── flink-on-eks/
│   └── spark-on-eks/                   # Example blueprint
│       ├── terraform/                  # AWS infrastructure only
│       ├── examples/                   # Sample workloads  
│       └── values/                     # Karpenter NodePools/EC2NodeClass
├── infra/                              # Infrastructure modules and ArgoCD
│   ├── argocd/                         # ArgoCD-managed addons
│   │   ├── core/                       # Essential addons (Karpenter, LB, Monitoring)
│   │   └── data/                       # Data platform addons (Spark, Flink, etc.)
│   └── terraform/                      # Base Terraform modules
│       ├── eks/                        # EKS cluster + ArgoCD + addons
│       ├── teams/                      # Team management
│       └── vpc/                        # Standardized VPC module
└── website/                            # Documentation website
```

## 📋 Blueprint Creation Standards

### Prerequisites
Before creating any blueprint, ensure you understand:
- Terraform module patterns used in `infra/terraform/`
- ArgoCD application structure in `infra/argocd/`
- Karpenter NodePool/EC2NodeClass patterns
- Security and RBAC requirements

## Step-by-Step Blueprint Creation (Example: flink-on-eks)

> **IMPORTANT**: Follow these steps exactly to maintain architectural consistency

### 1. Create Blueprint Directory Structure

```bash
mkdir -p blueprints/flink-on-eks/{terraform,examples,values}
```

### 2. Create Terraform Infrastructure

**terraform/main.tf**:
```hcl
locals {
  name   = var.name
  region = var.region
  tags = merge(var.tags, {
    Blueprint = local.name
  })
}

# Use base VPC module
module "vpc_blueprint" {
  source = "../../infra/terraform/vpc"
  
  name            = local.name
  vpc_cidr        = var.vpc_cidr
  secondary_cidrs = var.secondary_cidrs
  tags           = local.tags
}

# Use base EKS module  
module "eks_blueprint" {
  source = "../../infra/terraform/eks"
  
  name                           = local.name
  eks_cluster_version           = var.eks_cluster_version
  cluster_endpoint_public_access = var.cluster_endpoint_public_access
  
  vpc_id                      = module.vpc_blueprint.vpc_id
  private_subnets            = module.vpc_blueprint.private_subnets
  private_subnets_cidr_blocks = module.vpc_blueprint.private_subnets_cidr_blocks
  
  tags = local.tags
}
```

**terraform/variables.tf**:
```hcl
variable "name" {
  description = "Name of the blueprint"
  type        = string
  default     = "flink-on-eks"
}

variable "region" {
  description = "AWS region"  
  type        = string
  default     = "us-west-2"
}

# Include standard variables from base modules
variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.1.0.0/16"
}

variable "eks_cluster_version" {
  description = "EKS cluster version"
  type        = string
  default     = "1.31"
}
```

### 3. Create Karpenter Resources

**values/nodepool-flink-compute.yaml**:
```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: flink-compute
spec:
  template:
    metadata:
      labels:
        workload-type: "flink"
    spec:
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: flink-compute
      
      taints:
        - key: "flink.apache.org/compute"
          value: "true"
          effect: NoSchedule
      
      startupTaints:
        - key: "flink.apache.org/compute"
          value: "true"
          effect: NoSchedule
      
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["spot", "on-demand"]
        - key: "kubernetes.io/arch"
          operator: In
          values: ["amd64"]
        - key: "node.kubernetes.io/instance-type"
          operator: In
          values: ["m5.large", "m5.xlarge", "m5.2xlarge", "m5.4xlarge"]
  
  limits:
    cpu: 1000
  
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
    expireAfter: 30m
```

### 4. Add ArgoCD Bootstrap

**terraform/argocd-applications.tf**:
```hcl
# Deploy Flink Operator from infra/argocd/data/
resource "kubectl_manifest" "flink_operator" {
  yaml_body = file("../../infra/argocd/data/flink-operator.yaml")
  depends_on = [module.eks_blueprint]
}

# Deploy Karpenter NodePool
resource "kubectl_manifest" "flink_nodepool" {  
  yaml_body = file("${path.module}/../values/nodepool-flink-compute.yaml")
  depends_on = [kubectl_manifest.flink_operator]
}
```

### 5. Create Deployment Script

**deploy-blueprint.sh** (copy from spark-on-eks and modify):
```bash
#!/bin/bash
set -e

BLUEPRINT_NAME="flink-on-eks"
# ... rest similar to spark-on-eks script
```

## 🔒 Mandatory Architecture Rules

### Rule 1: Infrastructure Separation
```
✅ DO: Use only infra/terraform/vpc and infra/terraform/eks modules
❌ DON'T: Create custom VPC or EKS resources in blueprints
❌ DON'T: Duplicate any infrastructure code
```

### Rule 2: ArgoCD Integration
```
✅ DO: Reference existing ArgoCD applications from infra/argocd/
✅ DO: Use terraform/argocd-applications.tf for Kubernetes resource deployment
❌ DON'T: Create Helm releases directly in Terraform
❌ DON'T: Deploy Kubernetes resources outside ArgoCD workflow
```

### Rule 3: Standard Directory Structure
```
✅ REQUIRED: blueprints/blueprint-name/terraform/
✅ REQUIRED: blueprints/blueprint-name/examples/
✅ REQUIRED: blueprints/blueprint-name/values/
✅ REQUIRED: blueprints/blueprint-name/deploy-blueprint.sh
❌ FORBIDDEN: Any other top-level directories
```

### Rule 4: Security & RBAC
```
✅ DO: Use IRSA (IAM Roles for Service Accounts) for all AWS access
✅ DO: Apply least-privilege principle
✅ DO: Include security scanning and validation
❌ DON'T: Hard-code credentials or use overly permissive policies
```

### Rule 5: Documentation Standards
```
✅ REQUIRED: Blueprint README.md with deployment steps
✅ REQUIRED: Example workloads in examples/ directory
✅ REQUIRED: Clear variable descriptions in variables.tf
❌ DON'T: Skip documentation or provide incomplete examples
```

## Deployment Commands

```bash
# Deploy any blueprint
cd blueprints/blueprint-name
./deploy-blueprint.sh

# Access ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get ArgoCD password  
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Verify applications
kubectl get applications -n argocd
```

## 🚀 Blueprint Update Guidelines

### When Updating Existing Blueprints
1. **Check Dependencies**: Ensure base modules (`infra/terraform/`) support your changes
2. **Version Compatibility**: Test with current EKS/Kubernetes versions
3. **Backward Compatibility**: Don't break existing deployments
4. **Documentation**: Update README and examples accordingly

### Common Update Scenarios
```bash
# Updating Terraform modules
cd blueprints/your-blueprint/terraform
terraform plan  # Review changes
terraform apply

# Updating ArgoCD applications
# Edit infra/argocd/data/your-app.yaml
# ArgoCD will auto-sync changes

# Updating Karpenter resources
# Edit blueprints/your-blueprint/values/nodepool-*.yaml
# Redeploy via kubectl apply
```

## 🏗️ Architecture Benefits

### For Users
- **🚀 70% faster deployment** - Standardized patterns reduce setup time
- **🔒 Production-grade security** - Built-in RBAC and least-privilege access
- **📊 Comprehensive monitoring** - Grafana dashboards and alerts included
- **💰 Cost optimization** - Karpenter-based autoscaling and spot instances

### For Maintainers  
- **🔄 Centralized updates** - Fix once in base modules, applies everywhere
- **🧪 Consistent testing** - Standardized validation and CI/CD patterns
- **📚 Reduced documentation burden** - Common patterns documented once
- **🛠️ Easier troubleshooting** - Uniform architecture across blueprints

## 🎯 Success Metrics
- **Code Duplication**: <30% (down from 70-80%)
- **Deployment Time**: <15 minutes for complete stack
- **Security Compliance**: 100% IRSA adoption
- **Documentation Coverage**: >95% of blueprints documented

## 🛠️ Development Workflow

### Before Creating/Updating Any Blueprint
1. **Read this document completely** - Non-negotiable requirement
2. **Study existing blueprints** - Use spark-on-eks as reference implementation
3. **Check infra/argocd/** - Understand available ArgoCD applications
4. **Test locally** - Validate your changes work end-to-end

### Code Review Checklist
- [ ] Follows mandatory architecture rules
- [ ] Uses base modules only (`infra/terraform/vpc`, `infra/terraform/eks`)
- [ ] ArgoCD integration implemented correctly
- [ ] Documentation complete and accurate  
- [ ] Examples provided and tested
- [ ] Security best practices applied
- [ ] No code duplication introduced

### Approval Process
- **Architecture Review**: Must follow this guide's principles
- **Security Review**: IRSA, least-privilege, no hardcoded secrets
- **Documentation Review**: Complete and user-friendly
- **Testing**: End-to-end deployment validation

## 📞 Support & Contribution

### Getting Help
- **Architecture Questions**: Reference this document first
- **Technical Issues**: Check existing blueprint implementations
- **Security Concerns**: Follow IRSA and least-privilege patterns
- **Documentation**: Use clear, concise language with examples

### Contributing Guidelines
1. **Follow this architecture guide** - No exceptions
2. **Test thoroughly** - Your blueprint must deploy successfully
3. **Document completely** - Others will use your work
4. **Review existing patterns** - Don't reinvent the wheel

---

**Remember**: This architecture guide is the **single source of truth** for all Data-on-EKS blueprint development. Adherence to these principles ensures consistency, maintainability, and production-readiness across the entire platform.