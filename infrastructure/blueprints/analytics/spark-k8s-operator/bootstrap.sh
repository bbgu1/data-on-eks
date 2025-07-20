#!/bin/bash

set -e

echo "=== DoEKS v2.0 - Spark K8s Operator Blueprint Bootstrap ==="
echo

# Check if region is provided
if [ -z "$1" ]; then
  read -p "Enter the AWS region: " region
else
  region=$1
fi

# Set AWS region environment variables to ensure consistency
export AWS_DEFAULT_REGION=$region
export AWS_REGION=$region

echo "Using AWS region: $region"
echo

# Navigate to terraform directory
cd terraform

# Check if terraform.tfvars exists
if [ ! -f terraform.tfvars ]; then
  echo "Creating terraform.tfvars from example..."
  cp terraform.tfvars.example terraform.tfvars
  
  # Update region in terraform.tfvars
  sed -i.bak "s/region = \".*\"/region = \"$region\"/" terraform.tfvars
  rm terraform.tfvars.bak
  
  echo "Please review and update terraform.tfvars if needed."
  echo "Press Enter to continue..."
  read
fi

echo "=== Step 1: Initialize Terraform ==="
terraform init -upgrade

echo
echo "=== Step 2: Plan Infrastructure ==="
terraform plan -var="region=$region"

echo
read -p "Proceed with deployment? (y/N): " proceed
if [[ ! $proceed =~ ^[Yy]$ ]]; then
  echo "Deployment cancelled."
  exit 0
fi

echo
echo "=== Step 3: Deploy Base Infrastructure ==="

# List of modules to apply in sequence for dependency management
targets=(
  "module.vpc"
  "module.eks"
)

# Apply core infrastructure modules in sequence
for target in "${targets[@]}"; do
  echo "Deploying $target..."
  if ! terraform apply -target="$target" -var="region=$region" -auto-approve; then
    echo "ERROR: Failed to deploy $target"
    exit 1
  fi
  echo "✅ $target deployed successfully"
  echo
done

echo "=== Step 4: Deploy Remaining Resources ==="
if ! terraform apply -var="region=$region" -auto-approve; then
  echo "ERROR: Failed to deploy remaining resources"
  exit 1
fi

echo
echo "=== Step 5: Configure kubectl ==="
cluster_name=$(terraform output -raw cluster_name)
aws eks --region $region update-kubeconfig --name $cluster_name

echo
echo "=== Step 6: Wait for EKS cluster to be ready ==="
echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=600s

echo
echo "=== Deployment Summary ==="
echo "✅ Infrastructure deployed successfully!"
echo
echo "Cluster Name: $cluster_name"
echo "Region: $region"
echo "S3 Bucket: $(terraform output -raw s3_bucket_name)"
echo
echo "=== Next Steps ==="
echo "1. Deploy ArgoCD applications:"
echo "   kubectl apply -f argocd-apps/"
echo
echo "2. Access ArgoCD UI:"
echo "   $(terraform output -raw configure_argocd)"
echo "   Username: admin"
echo "   Password: \$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d)"
echo
echo "3. Deploy Karpenter NodePools:"
echo "   kubectl apply -k karpenter-resources/"
echo
echo "4. Run Spark examples:"
echo "   kubectl apply -f examples/karpenter/"
echo
echo "=== Troubleshooting ==="
echo "• Check cluster status: kubectl get nodes"
echo "• Check ArgoCD: kubectl get pods -n argocd"
echo "• Check Karpenter: kubectl get pods -n karpenter"
echo "• View logs: kubectl logs -f deployment/karpenter -n karpenter"