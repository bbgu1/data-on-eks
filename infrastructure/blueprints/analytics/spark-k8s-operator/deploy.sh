#!/bin/bash

set -e

echo "=== Spark K8s Operator Blueprint Deployment ==="
echo "This script will deploy ONLY the Spark K8s Operator blueprint"
echo "Blueprint: analytics/spark-k8s-operator"
echo

# Safety check - ensure we're in the right directory
EXPECTED_PATH="infrastructure/blueprints/analytics/spark-k8s-operator"
CURRENT_PATH=$(pwd | grep -o "$EXPECTED_PATH" || echo "")

if [[ "$CURRENT_PATH" != "$EXPECTED_PATH" ]]; then
    echo "❌ ERROR: This script must be run from the spark-k8s-operator blueprint directory"
    echo "Current: $(pwd)"
    echo "Expected: */$EXPECTED_PATH"
    exit 1
fi

# Get region
if [ -z "$1" ]; then
    read -p "Enter AWS region (default: us-west-2): " region
    region=${region:-us-west-2}
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

# Navigate to terraform directory
cd terraform

# Check if terraform.tfvars exists
if [ ! -f terraform.tfvars ]; then
    echo "📝 Creating terraform.tfvars..."
    cat > terraform.tfvars << EOF
# Spark K8s Operator Blueprint Configuration
name                           = "spark-k8s-operator"
region                         = "$region"
eks_cluster_version            = "1.33"
cluster_endpoint_public_access = true

# VPC Configuration
vpc_cidr        = "10.0.0.0/16"
secondary_cidrs = ["100.64.0.0/16"]

# KMS Key Admin Roles (add your IAM roles here)
kms_key_admin_roles = []

# Add-ons Configuration
enable_mountpoint_s3_csi        = true
enable_cloudwatch_observability = true
enable_yunikorn                 = false
enable_jupyterhub               = false
EOF
    echo "✅ terraform.tfvars created with default values"
    echo "📋 Review and update terraform.tfvars if needed"
    echo
fi

echo "=== Step 1: Initialize Terraform ==="
terraform init -upgrade

echo
echo "=== Step 2: Plan Deployment ==="
terraform plan -var="region=$region"

echo
read -p "Proceed with deployment? (y/N): " proceed
if [[ ! $proceed =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

echo
echo "=== Step 3: Deploy Infrastructure ==="

# Deploy core modules first
core_modules=(
    "module.vpc"
    "module.eks"
)

for module in "${core_modules[@]}"; do
    echo "🔧 Deploying $module..."
    if ! terraform apply -target="$module" -var="region=$region" -auto-approve; then
        echo "❌ ERROR: Failed to deploy $module"
        echo "💡 Run './cleanup.sh $region' to clean up and try again"
        exit 1
    fi
    echo "✅ $module deployed successfully"
done

echo
echo "🔧 Deploying remaining resources..."
if ! terraform apply -var="region=$region" -auto-approve; then
    echo "❌ ERROR: Failed to deploy remaining resources"
    echo "💡 Run './cleanup.sh $region' to clean up and try again"
    exit 1
fi

echo
echo "=== Step 4: Configure kubectl ==="
cluster_name=$(terraform output -raw cluster_name)
aws eks --region $region update-kubeconfig --name $cluster_name

echo
echo "=== Step 5: Wait for cluster readiness ==="
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
echo "4. Test with Spark examples:"
echo "   kubectl apply -f ../examples/karpenter/"
echo