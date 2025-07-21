#!/bin/bash

set -e

echo "=== Spark K8s Operator Blueprint Deployment ==="
echo "This script will deploy ONLY the Spark K8s Operator blueprint"
echo "Blueprint: analytics/spark-on-eks"
echo

# Safety check - ensure we're in the right directory
EXPECTED_PATH="blueprints/spark-on-eks/terraform"
CURRENT_PATH=$(pwd | grep -o "$EXPECTED_PATH" || echo "")

if [[ "$CURRENT_PATH" != "$EXPECTED_PATH" ]]; then
    echo "❌ ERROR: This script must be run from the spark-on-eks blueprint directory"
    echo "Current: $(pwd)"
    echo "Expected: */$EXPECTED_PATH"
    exit 1
fi

# Get region
if [ -z "$1" ]; then
    read -p "Enter AWS region (default: us-east-1): " region
    region=${region:-us-east-1}
else
    region=$1
fi

# Set AWS environment variables
export AWS_DEFAULT_REGION=$region
export AWS_REGION=$region

echo "🚀 Deploying Spark K8s Operator Blueprint"
echo "Region: $region"
echo "Blueprint: $(pwd)"
echo

# List of Terraform modules to apply in sequence
targets=(
  "module.vpc"
  "module.eks"
)

echo "=== Step 1: Initialize Terraform ==="
terraform init -upgrade

# Check if terraform.tfvars exists
if [ -f "terraform.tfvars" ]; then
  TERRAFORM_COMMAND="$TERRAFORM_COMMAND -var-file=terraform.tfvars"
fi

echo
echo "=== Step 2: Plan Deployment ==="
terraform plan -var-file=terraform.tfvars

echo
echo "=== Step 3: Apply Deployment ==="
# Apply modules in sequence
for target in "${targets[@]}"
do
  echo "Applying module $target..."
  apply_output=$( $TERRAFORM_COMMAND -target="$target" 2>&1 | tee /dev/tty)
  if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
    echo "SUCCESS: Terraform apply of $target completed successfully"
  else
    echo "FAILED: Terraform apply of $target failed"
    exit 1
  fi
done

# Final apply to catch any remaining resources
echo "Applying remaining resources..."
apply_output=$( $TERRAFORM_COMMAND 2>&1 | tee /dev/tty)
if [[ ${PIPESTATUS[0]} -eq 0 && $apply_output == *"Apply complete"* ]]; then
  echo "SUCCESS: Terraform apply of all modules completed successfully"
else
  echo "FAILED: Terraform apply of all modules failed"
  exit 1
fi

echo
echo "=== Step 3: Configure kubectl ==="
cluster_name=$(terraform output -raw cluster_name)
aws eks --region $region update-kubeconfig --name $cluster_name

echo
echo "=== Step 4: Wait for cluster readiness ==="
echo "⏳ Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=600s

echo
echo "🎉 Deployment Complete!"
echo
echo "=== Deployment Summary ==="
echo "✅ Cluster Name: $cluster_name"
echo "✅ Region: $region"
echo "✅ S3 Bucket: $(terraform output -raw s3_bucket_name)"
echo
echo "=== Next Steps ==="
echo "1. Deploy ArgoCD applications:"
echo "   kubectl apply -f ../argocd-apps/"
echo
echo "2. Access ArgoCD UI:"
echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "   Username: admin"
echo "   Password: \$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo
echo "3. Deploy Karpenter NodePools:"
echo "   kubectl apply -k ../karpenter-resources/"
echo
