# Spark Operator on EKS Blueprint

This blueprint deploys Apache Spark on Amazon EKS using the Kubernetes Spark Operator and Karpenter for dynamic node scaling.

## Architecture

This blueprint uses the new **Data-on-EKS v2 architecture** with clear separation of concerns:

- **Terraform**: AWS infrastructure only (VPC, EKS, IAM, S3)
- **ArgoCD**: Kubernetes applications (Spark Operator, Karpenter NodePools, Monitoring)
- **GitOps**: All K8s resources managed via ArgoCD applications

### Directory Structure

```
blueprints/spark-on-eks/
├── terraform/                 # Infrastructure as Code
│   ├── deploy.sh             # 🚀 MAIN DEPLOYMENT SCRIPT
│   ├── cleanup.sh            # Cleanup script
│   ├── main.tf               # Terraform configuration
│   ├── pod-identity.tf       # Spark Pod Identity roles
│   ├── variables.tf          # Variable definitions
│   └── outputs.tf            # Output values
├── composition.yaml          # ArgoCD ApplicationSet (GitOps)
├── values/                   # Blueprint-specific overrides
│   └── dev/                  # Environment-specific values
│       ├── karpenter.yaml           # 12 Spark NodePools config
│       ├── spark-operator.yaml      # Spark Operator config
│       ├── spark-history-server.yaml # History Server config
│       ├── prometheus-stack.yaml    # Monitoring config
│       ├── aws-load-balancer-controller.yaml
│       └── yunikorn.yaml           # Optional scheduler
└── examples/                 # Spark job examples
    ├── karpenter/           # Karpenter-optimized jobs
    ├── benchmark/           # Performance testing
    ├── docker/              # Custom Docker images
    ├── mountpoint-s3-spark/ # S3 integration examples
    └── s3-tables/           # S3 Tables examples
```

### Addon Library Structure (Reusable)

```
infra/argocd/                 # Reusable addon library
├── core/                    # Infrastructure addons
│   ├── karpenter/
│   └── aws-load-balancer-controller/
├── data/                    # Data platform addons
│   ├── spark-operator/
│   ├── spark-history-server/
│   └── yunikorn/
└── observability/           # Monitoring addons
    └── prometheus-stack/
```

### Deployment Flow

1. **Terraform** deploys AWS infrastructure (VPC, EKS, Pod Identity)
2. **ArgoCD App of Apps** bootstraps all Kubernetes applications
3. **Sync Wave 1**: App of Apps (bootstrap)
4. **Sync Wave 2**: Karpenter NodePools (infrastructure)
5. **Sync Wave 3**: Spark Operator (application)
6. **Sync Wave 4**: Spark History Server (monitoring)

## Quick Start

### 1. Deploy Infrastructure

**Use the deployment script in the `terraform/` folder:**

```bash
cd blueprints/spark-on-eks/terraform
./deploy.sh us-west-2  # Replace with your desired region
```

This script will:
- ✅ Deploy VPC and EKS cluster
- ✅ Configure Pod Identity for Spark workloads  
- ✅ Set up S3 bucket for Spark event logs
- ✅ Install ArgoCD for GitOps
- ✅ Deploy all Spark addons via ArgoCD ApplicationSet

### 2. Verify Deployment

Check ArgoCD applications:
```bash
kubectl get applications -n argocd
```

Check Karpenter NodePools:
```bash
kubectl get nodepools -n karpenter
```

### 3. Cleanup

```bash
cd blueprints/spark-on-eks/terraform
./cleanup.sh us-west-2  # Replace with your region
```

### Alternative: Manual Deployment

```bash
cd blueprints/spark-on-eks/terraform

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy using the provided script
./deploy.sh us-west-2

# Or manually:
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### 2. Configure kubectl

```bash
# Get cluster name from Terraform output
cluster_name=$(terraform output -raw cluster_name)
aws eks --region <region> update-kubeconfig --name $cluster_name
```

### 3. Deploy Applications via ArgoCD

```bash
# Deploy the Spark stack (App of Apps pattern)
kubectl apply -f ../argocd-apps/spark-app-of-apps.yaml

# Monitor ArgoCD deployments
kubectl get applications -n argocd

# Port forward to ArgoCD UI (optional)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access ArgoCD UI at https://localhost:8080
# Username: admin
# Password: Get from secret
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## What's Deployed

### AWS Infrastructure (Terraform)
- **VPC**: Multi-AZ VPC with public/private subnets and secondary CIDR
- **EKS Cluster**: Kubernetes 1.31 with managed node groups
- **EKS Add-ons**: CoreDNS, VPC-CNI, EBS CSI, Mountpoint S3 CSI
- **ArgoCD**: Installed via Terraform for GitOps workflows
- **Karpenter**: Node provisioning and lifecycle management
- **S3 Bucket**: For Spark event logs and data storage
- **Pod Identity**: Modern replacement for IRSA (IAM Roles for Service Accounts)

### Kubernetes Applications (ArgoCD)
- **Spark Operator**: Kubernetes-native Spark job management with Pod Identity
- **Karpenter NodePools**: Auto-scaling v1.6 NodePools with EC2NodeClasses
- **Spark History Server**: Web UI for completed Spark jobs with S3 integration
- **GitOps Management**: All resources managed via ArgoCD with automatic sync
- **Health Monitoring**: ArgoCD health checks for all deployed applications

### ArgoCD Applications

| Application | Description | Sync Wave | Features |
|-------------|-------------|-----------|----------|
| `spark-app-of-apps` | Bootstrap application | Wave 1 | App of Apps pattern |
| `karpenter-spark-nodepools` | Node provisioning | Wave 2 | v1.6 API, disruption budgets |
| `spark-operator` | Spark job management | Wave 3 | Pod Identity, HA setup |
| `spark-history-server` | Job monitoring | Wave 4 | S3 integration, Pod Identity |

## Key Features

### 🚀 **Modern GitOps Architecture**
- **Infrastructure as Code**: All AWS resources via Terraform
- **Applications as Code**: All K8s apps via ArgoCD (including Karpenter resources)
- **No Manual kubectl**: All changes through Git commits
- **Automatic Sync**: ArgoCD monitors Git and applies changes automatically
- **Health Monitoring**: Continuous health checks and automatic remediation

### ⚡ **Auto-Scaling Spark**
- **Karpenter v1.6**: Latest stable API for dynamic node provisioning
- **Multiple Node Types**: Compute-optimized, memory-optimized with startup taints
- **Spot Instance Support**: Cost optimization with disruption budgets
- **Instance Store Optimization**: RAID0 configuration for Spark shuffle
- **Multi-Architecture**: AMD64 and ARM64 (Graviton) support

### 📊 **Observability**
- **Spark Metrics**: Prometheus metrics from Spark Operator
- **History Server**: Web UI for job monitoring and debugging
- **Cost Tracking**: Kubecost for workload cost attribution

### 🔒 **Security & Compliance**
- **Pod Identity**: Modern IAM roles for service accounts (replaces IRSA)
- **Network Isolation**: Private subnets for worker nodes
- **Encryption**: EBS and S3 encryption by default
- **Production-ready**: Non-root containers, security contexts, network policies

## Configuration

### Infrastructure Variables

Key variables in `terraform.tfvars`:

```hcl
# Cluster configuration
name                           = "spark-on-eks"
region                         = "us-west-2"
eks_cluster_version            = "1.33"
environment                    = "dev"

# VPC configuration (uses shared VPC module)
vpc_cidr                       = "10.0.0.0/16"
secondary_cidrs                = ["100.64.0.0/16"]

# Features
enable_mountpoint_s3_csi       = true
enable_cloudwatch_observability = true
enable_pod_identity            = true

# Tags
tags = {
  Blueprint   = "spark-on-eks"
  Environment = "dev"
  ManagedBy   = "terraform"
}
```

### ArgoCD Applications

Customize applications by modifying files in `argocd-apps/`:

- `spark-app-of-apps.yaml`: Bootstrap application (App of Apps pattern)
- `spark-operator.yaml`: Spark Operator with Pod Identity integration
- `karpenter-spark-nodepools.yaml`: Karpenter v1.6 NodePools and EC2NodeClasses
- `spark-history-server.yaml`: History server with Pod Identity
- `values-configmap.yaml`: Centralized configuration values

## Karpenter GitOps Management

All Karpenter resources are now managed by ArgoCD, eliminating the need for manual `kubectl apply` commands:

### How It Works

1. **Modify** Karpenter resources in `karpenter-resources/` directory
2. **Commit** changes to your Git repository
3. **ArgoCD automatically syncs** changes within the configured sync interval
4. **Health checks** validate that NodePools and EC2NodeClasses are ready
5. **Rollback** capabilities if issues are detected

### Karpenter Resources

The `karpenter-spark-nodepools` ArgoCD application manages:

```bash
karpenter-resources/
├── spark-compute-optimized.yaml    # Compute NodePool + EC2NodeClass
├── spark-memory-optimized.yaml     # Memory NodePool + EC2NodeClass
├── kustomization.yaml             # Kustomize patches for values
└── README.md                      # Detailed documentation
```

### Dynamic Value Replacement

ArgoCD automatically replaces placeholder values with actual cluster configuration:

- `PLACEHOLDER_CLUSTER_NAME` → Your EKS cluster name
- `PLACEHOLDER_KARPENTER_NODE_INSTANCE_PROFILE` → IAM instance profile ARN  
- `PLACEHOLDER_ENVIRONMENT` → Environment tag (dev/staging/prod)

### Monitoring Karpenter via ArgoCD

```bash
# Check ArgoCD application status
kubectl get application karpenter-spark-nodepools -n argocd

# View Karpenter resources
kubectl get nodepools -n karpenter
kubectl get ec2nodeclasses -n karpenter

# Force ArgoCD sync if needed
argocd app sync karpenter-spark-nodepools
```

## Usage Examples

### Submit a Spark Job

```bash
kubectl apply -f examples/karpenter/pyspark-pi-job.yaml
```

### Monitor Jobs

```bash
# Spark Operator metrics
kubectl port-forward svc/spark-operator-metrics -n spark-operator 8080:8080

# Spark History Server
kubectl port-forward svc/spark-history-server -n spark-history-server 18080:80

# Grafana dashboards
kubectl port-forward svc/kube-prometheus-stack-grafana -n kube-prometheus-stack 3000:80
```

### Scaling Tests

```bash
# Run benchmark workloads
kubectl apply -f examples/benchmark/tpcds-benchmark-1t-ssd.yaml
```

## Migration from v1

This blueprint replaces the legacy `analytics/terraform/spark-k8s-operator/` structure:

### What Changed
- ✅ **Eliminated duplicate code**: Shared VPC/EKS modules
- ✅ **Removed addon modules**: `eks_blueprints_addons` → ArgoCD apps
- ✅ **GitOps-native**: Helm values embedded in ArgoCD applications
- ✅ **Simplified structure**: Everything in one blueprint folder

### What's New in v2

- ✅ **Pod Identity**: Replaces IRSA for better security and performance
- ✅ **Karpenter v1.6**: Stable API with advanced features
- ✅ **Shared Infrastructure**: VPC and EKS modules reused across blueprints
- ✅ **Blueprint-specific IAM**: Spark roles moved from infra to blueprint
- ✅ **Enhanced ArgoCD**: Health checks, sync waves, retry policies
- ✅ **Production Ready**: Non-root containers, network policies, disruption budgets

### Migration Steps
1. **Deploy new blueprint**: `./deploy.sh <region>`
2. **Migrate workloads**: Copy Spark jobs to new cluster
3. **Update CI/CD**: Point to new ArgoCD applications
4. **Verify functionality**: Run test jobs and monitoring
5. **Deprecate old**: Remove legacy blueprint when ready

## Troubleshooting

### Common Issues

**ArgoCD apps not syncing:**
```bash
# Check ArgoCD status
kubectl get applications -n argocd

# Force sync (updated app name)
argocd app sync spark-on-eks-stack

# Check sync waves and health
kubectl describe application spark-on-eks-stack -n argocd
```

**Karpenter nodes not launching:**
```bash
# Check Karpenter v1.6 resources
kubectl get nodepools -n karpenter
kubectl get ec2nodeclasses -n karpenter
kubectl describe nodepool spark-compute-optimized -n karpenter

# Check Karpenter operator logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter

# Verify Pod Identity association
kubectl describe podidentityassociation -n karpenter
```

**Spark jobs failing:**
```bash
# Check operator logs
kubectl logs -n spark-operator -l app.kubernetes.io/name=spark-operator

# Check job status
kubectl get sparkapplications
kubectl describe sparkapplication <job-name>
```

## Resources

- [Spark Operator Documentation](https://googlecloudplatform.github.io/spark-on-k8s-operator/)
- [Karpenter Documentation](https://karpenter.sh/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Data-on-EKS Website](https://awslabs.github.io/data-on-eks/)

## Support

- [GitHub Issues](https://github.com/awslabs/data-on-eks/issues)
- [AWS Support](https://aws.amazon.com/support/)
- [Community Slack](https://join.slack.com/t/cncf/shared_invite/zt-foo)