# Data on EKS - Developer Guide

Quick reference for developers contributing to Data on EKS platform.

## Repository Structure

```
data-on-eks/
├── blueprints/                     # Complete deployment examples
│   └── spark-on-eks/              # Example blueprint
│       ├── terraform/              # Infrastructure code
│       ├── examples/               # Sample workloads
│       └── deploy-blueprint.sh     # Deployment script
├── infra/                          # Shared infrastructure components  
│   ├── terraform/                  # Terraform modules
│   │   ├── argocd-addons/         # ArgoCD addon definitions
│   │   ├── eks/                   # EKS cluster module
│   │   ├── vpc/                   # VPC module
│   │   ├── teams/                 # Team namespace module
│   │   └── irsa/                  # IRSA module
│   ├── argocd-applications/       # ArgoCD app templates
│   └── karpenter-resources/       # Karpenter node pools
└── docs/                          # Documentation (this folder)
```

## Quick Commands

### Deploy Blueprint
```bash
cd blueprints/spark-on-eks/terraform
terraform init && terraform apply -auto-approve
```

### Check ArgoCD Apps
```bash
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
```

### Debug Pods
```bash
kubectl get pods -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
```

---

## 1. Adding New ArgoCD Addon

**Example: Adding PostgreSQL**

### Step 1: Create Terraform File
`infra/terraform/argocd-addons/postgresql.tf`

```hcl
locals {
  postgresql_name = "postgresql"
  
  # Default values (only override helm chart defaults)
  postgresql_default_values = yamldecode(<<-EOT
    auth:
      database: "mydatabase"
      username: "myuser"
    primary:
      persistence:
        size: 100Gi
        storageClass: "gp3"
  EOT
  )

  # Merge user values
  postgresql_user = try(yamldecode(try(var.postgresql_helm_config.values[0], "")), {})
  postgresql_values_map = merge(local.postgresql_default_values, local.postgresql_user)
}

# ArgoCD Application Resource
resource "kubectl_manifest" "postgresql" {
  count = var.enable_postgresql ? 1 : 0

  yaml_body = templatefile("${path.module}/../../../infra/argocd-applications/postgresql.yaml", {
    user_values_yaml = indent(8, yamlencode(local.postgresql_values_map))
  })
}
```

### Step 2: Create ArgoCD Application
`infra/argocd-applications/postgresql.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: postgresql
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # Deploy order
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: postgresql
    targetRevision: "12.1.2"  # Specific version
    helm:
      valuesObject:
        ${user_values_yaml}
  destination:
    server: https://kubernetes.default.svc
    namespace: postgresql
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    automated:
      prune: true
      selfHeal: true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### Step 3: Add Variables
Add to `infra/terraform/argocd-addons/variables.tf`:

```hcl
variable "enable_postgresql" {
  description = "Enable PostgreSQL addon"
  type        = bool
  default     = false
}

variable "postgresql_helm_config" {
  description = "PostgreSQL Helm Chart config"
  type        = any
  default     = {}
}
```

### Step 4: Use in Blueprint
`blueprints/my-blueprint/terraform/main.tf`:

```hcl
module "argocd_addons" {
  source = "../../../infra/terraform/argocd-addons"
  
  enable_postgresql = true
  postgresql_helm_config = {
    values = [
      <<-EOT
        auth:
          database: "myapp"
          username: "appuser"
        primary:
          persistence:
            size: 200Gi
      EOT
    ]
  }
}
```

---

## 2. Creating New Blueprint

**Example: Creating `kafka-on-eks` blueprint**

### Step 1: Create Blueprint Structure
```bash
mkdir -p blueprints/kafka-on-eks/{terraform,examples}
```

### Step 2: Blueprint Terraform
`blueprints/kafka-on-eks/terraform/main.tf`

```hcl
# VPC Module
module "vpc" {
  source = "../../../infra/terraform/vpc"
  cluster_name = local.cluster_name
}

# EKS Cluster  
module "eks" {
  source = "../../../infra/terraform/eks"
  cluster_name = local.cluster_name
  vpc_id = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
}

# ArgoCD Addons
module "argocd_addons" {
  source = "../../../infra/terraform/argocd-addons"
  
  cluster_name = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  
  # Enable addons
  enable_kafka = true
  kafka_helm_config = {
    values = [
      <<-EOT
        replicas: 3
        persistence:
          size: 100Gi
        zookeeper:
          replicas: 3
      EOT
    ]
  }
  
  enable_karpenter_resources = true
}

# Teams (optional)
module "teams" {
  source = "../../../infra/terraform/teams"
  
  cluster_name = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  
  teams = {
    kafka-team-a = {
      users = ["user1@company.com"]
    }
  }
}

locals {
  cluster_name = var.cluster_name
  region = var.region
}
```

### Step 3: Variables & Outputs
`blueprints/kafka-on-eks/terraform/variables.tf`

```hcl
variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "kafka-on-eks"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}
```

`blueprints/kafka-on-eks/terraform/outputs.tf`

```hcl
output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
```

### Step 4: Deploy Script
`blueprints/kafka-on-eks/deploy-blueprint.sh`

```bash
#!/bin/bash
set -e

# Configuration
BLUEPRINT_NAME="kafka-on-eks"
TERRAFORM_DIR="terraform"
REGION="us-west-2"

echo "🚀 Deploying ${BLUEPRINT_NAME} Blueprint"

# Deploy infrastructure
cd ${TERRAFORM_DIR}
terraform init
terraform apply -auto-approve

# Get cluster info
CLUSTER_NAME=$(terraform output -raw cluster_name)
echo "✅ Infrastructure deployed: ${CLUSTER_NAME}"

# Configure kubectl
aws eks update-kubeconfig --region ${REGION} --name ${CLUSTER_NAME}
echo "✅ kubectl configured"

# Wait for ArgoCD apps
echo "⏳ Waiting for ArgoCD applications..."
kubectl wait --for=condition=Synced application/kafka -n argocd --timeout=300s

echo "🎉 ${BLUEPRINT_NAME} deployment complete!"
echo "🔗 Check ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
```

---

## 3. Debugging Deployments

### Terraform Issues

**Check Plan**
```bash
terraform plan -out=debug.tfplan
terraform show debug.tfplan
```

**State Issues**
```bash
terraform state list
terraform state show <resource>
terraform refresh
```

**Provider Issues**  
```bash
terraform providers
terraform init -upgrade
```

### ArgoCD Issues

**App Status**
```bash
# List all applications
kubectl get applications -n argocd

# Detailed status
kubectl describe application <app-name> -n argocd

# App logs
kubectl logs -n argocd deployment/argocd-application-controller | grep <app-name>
```

**Sync Issues**
```bash
# Manual sync
kubectl patch application <app-name> -n argocd --type='merge' -p='{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{}}}}'

# Check sync status
kubectl get application <app-name> -n argocd -o yaml | grep -A 10 "status:"

# Force refresh
kubectl annotate application <app-name> -n argocd argocd.argoproj.io/refresh=normal
```

### Pod Issues

**Basic Debugging**
```bash
kubectl get pods -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous container
```

**Multi-container Pods**
```bash
kubectl logs <pod-name> -c <container-name> -n <namespace>
kubectl exec -it <pod-name> -c <container-name> -n <namespace> -- /bin/sh
```

**Resource Issues**
```bash
kubectl top nodes
kubectl top pods -n <namespace>
kubectl describe node <node-name>
```

### Karpenter Issues

**Check Node Provisioning**
```bash
kubectl get nodepools
kubectl describe nodepool <nodepool-name>
kubectl get ec2nodeclasses
kubectl logs -n karpenter deployment/karpenter --tail=50
```

**Node Issues**
```bash
kubectl get nodes --show-labels
kubectl describe node <node-name>
kubectl get events --sort-by=.metadata.creationTimestamp
```

---

## 4. Adding Karpenter NodePools

### Step 1: Create NodePool YAML
`infra/karpenter-resources/nodepool-gpu.yaml`

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: gpu-nodepool
spec:
  # Disruption settings
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s
    expireAfter: 2160h # 90 days

  # Node requirements
  template:
    metadata:
      labels:
        NodeGroupType: gpu-workloads
        provisioner: karpenter
    spec:
      # Instance requirements
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: 
            - "p3.2xlarge"
            - "p3.8xlarge"
            - "p4d.2xlarge"
            - "g4dn.2xlarge"
            - "g5.2xlarge"

      # Taints for GPU nodes
      taints:
        - key: nvidia.com/gpu
          value: "true"
          effect: NoSchedule

      # Node configuration
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1
        kind: EC2NodeClass
        name: default
      
      # Kubelet configuration
      kubelet:
        maxPods: 110

  # Scaling limits
  limits:
    cpu: 10000
    memory: 10000Gi
    nvidia.com/gpu: 100

---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: gpu-nodeclass
spec:
  # AMI selection
  amiSelectorTerms:
    - tags:
        karpenter.sh/discovery: "gpu-cluster"
  
  # Instance configuration
  instanceStorePolicy: "RAID0"
  
  # User data for GPU drivers
  userData: |
    #!/bin/bash
    /etc/eks/bootstrap.sh gpu-cluster
    
    # Install GPU drivers
    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
      sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
      sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    sudo systemctl restart containerd

  # Security groups and subnets
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "gpu-cluster"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "gpu-cluster"
```

### Step 2: Add to Terraform
`infra/terraform/argocd-addons/karpenter-resources.tf`

```hcl
# Add GPU nodepool
resource "kubectl_manifest" "karpenter_nodepool_gpu" {
  count = var.enable_gpu_nodes ? 1 : 0
  
  yaml_body = templatefile("${path.module}/../../karpenter-resources/nodepool-gpu.yaml", {
    cluster_name = var.cluster_name
  })
}
```

### Step 3: Use in Workload
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-workload
spec:
  nodeSelector:
    NodeGroupType: gpu-workloads
  tolerations:
    - key: nvidia.com/gpu
      operator: Exists
      effect: NoSchedule
  containers:
    - name: gpu-app
      image: nvidia/cuda:11.0-base
      resources:
        limits:
          nvidia.com/gpu: 1
```

---

## 5. Best Practices

### Terraform
- Use specific versions in `targetRevision`
- Only override necessary helm values
- Use proper sync waves (0 = infrastructure, 1 = applications)
- Test with `terraform plan` before apply

### ArgoCD
- Use `CreateNamespace=true` for new namespaces
- Enable `automated: {prune: true, selfHeal: true}`
- Set appropriate `retry` policies
- Use sync waves for dependencies

### Development
- Test locally with `kind` or `minikube` 
- Use consistent naming conventions
- Document resource requirements
- Include example workloads

### Security
- Use IRSA for AWS permissions
- Apply least privilege principle
- Use separate namespaces for isolation
- Enable Pod Security Standards

---

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| `Module not installed` | Run `terraform init` |
| `ArgoCD app OutOfSync` | Check sync waves, manual sync |
| `Pod CrashLoopBackOff` | Check logs, resource limits, dependencies |
| `Karpenter no nodes` | Verify nodepool requirements, check logs |
| `IRSA permissions` | Check role policies and trust relationships |
| `Helm chart errors` | Validate values.yaml syntax |

---

## Getting Help

1. **Check logs**: Start with pod/controller logs
2. **Validate config**: Use `terraform plan` and `kubectl describe`
3. **Search issues**: Check GitHub issues for similar problems
4. **Documentation**: Refer to official docs for helm charts
5. **Community**: Join Data on EKS Slack/Discord

---

*For more examples, see existing blueprints in `blueprints/` directory.*