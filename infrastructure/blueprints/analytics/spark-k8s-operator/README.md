# Spark Operator on EKS Blueprint

This blueprint deploys Apache Spark on Amazon EKS using the Kubernetes Spark Operator and Karpenter for dynamic node scaling.

## Architecture

This blueprint uses the new **Data-on-EKS v2 architecture** with clear separation of concerns:

- **Terraform**: AWS infrastructure only (VPC, EKS, IAM, S3)
- **ArgoCD**: Kubernetes applications (Spark Operator, Karpenter NodePools, Monitoring)
- **GitOps**: All K8s resources managed via ArgoCD applications

## Quick Start

### 1. Deploy Infrastructure

```bash
cd infrastructure/blueprints/analytics/spark-k8s-operator/terraform

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy
terraform init
terraform apply
```

### 2. Configure kubectl

```bash
aws eks --region <region> update-kubeconfig --name spark-k8s-operator
```

### 3. Deploy Applications via ArgoCD

```bash
# Port forward to ArgoCD (if not using ingress)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Access ArgoCD UI at https://localhost:8080
# Username: admin
# Password: Get from secret
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Deploy the Spark stack
kubectl apply -f argocd-apps/spark-app-of-apps.yaml
```

## What's Deployed

### AWS Infrastructure (Terraform)
- **VPC**: Multi-AZ VPC with public/private subnets and secondary CIDR
- **EKS Cluster**: Kubernetes 1.31 with managed node groups
- **EKS Add-ons**: CoreDNS, VPC-CNI, EBS CSI, Mountpoint S3 CSI
- **ArgoCD**: Installed via Terraform for GitOps workflows
- **S3 Bucket**: For Spark event logs and data storage
- **IAM Roles**: For service accounts (IRSA)

### Kubernetes Applications (ArgoCD)
- **Spark Operator**: Kubernetes-native Spark job management
- **Karpenter NodePools**: Auto-scaling compute and memory optimized nodes
- **Spark History Server**: Web UI for completed Spark jobs
- **Monitoring**: Prometheus metrics and Grafana dashboards
- **Core Add-ons**: Load balancer controller, Ingress NGINX, Fluent Bit

## Key Features

### 🚀 **Modern GitOps Architecture**
- **Infrastructure as Code**: All AWS resources via Terraform
- **Applications as Code**: All K8s apps via ArgoCD
- **No Helm State**: Pure GitOps with ArgoCD application CRDs

### ⚡ **Auto-Scaling Spark**
- **Karpenter**: Dynamic node provisioning for Spark workloads
- **Multiple Node Types**: Compute-optimized, memory-optimized, Graviton
- **Spot Instance Support**: Cost optimization with EC2 Spot instances

### 📊 **Observability**
- **Spark Metrics**: Prometheus metrics from Spark Operator
- **History Server**: Web UI for job monitoring and debugging
- **Cost Tracking**: Kubecost for workload cost attribution

### 🔒 **Security & Compliance**
- **IRSA**: IAM roles for service accounts
- **Network Isolation**: Private subnets for worker nodes
- **Encryption**: EBS and S3 encryption by default

## Configuration

### Infrastructure Variables

Key variables in `terraform.tfvars`:

```hcl
# Cluster configuration
name                           = "spark-k8s-operator"
region                         = "us-west-2"
eks_cluster_version            = "1.31"

# VPC configuration
vpc_cidr                       = "10.0.0.0/16"
secondary_cidrs                = ["100.64.0.0/16"]

# Features
enable_mountpoint_s3_csi       = true
enable_cloudwatch_observability = true
enable_yunikorn                = false
```

### ArgoCD Applications

Customize applications by modifying files in `argocd-apps/`:

- `spark-operator.yaml`: Spark Operator configuration
- `karpenter-nodepool.yaml`: Node pool definitions  
- `spark-history-server.yaml`: History server settings

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

### Migration Steps
1. **Deploy new blueprint**: Start with fresh infrastructure
2. **Migrate workloads**: Copy Spark jobs to new cluster
3. **Update CI/CD**: Point to new ArgoCD applications
4. **Deprecate old**: Remove legacy blueprint when ready

## Troubleshooting

### Common Issues

**ArgoCD apps not syncing:**
```bash
# Check ArgoCD status
kubectl get applications -n argocd

# Force sync
argocd app sync spark-k8s-operator-stack
```

**Karpenter nodes not launching:**
```bash
# Check node pool status
kubectl get nodepools
kubectl describe nodepool spark-compute-optimized

# Check Karpenter logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
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