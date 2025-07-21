#!/bin/bash

set -e

echo "=== Spark K8s Operator Blueprint Cleanup ==="
echo "This script will cleanup ONLY the Spark K8s Operator blueprint"
echo "Blueprint: analytics/spark-k8s-operator"
echo

# Safety check - ensure we're in the right directory
EXPECTED_PATH="blueprints/analytics/spark-k8s-operator"
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

echo "🧹 Cleaning up Spark K8s Operator Blueprint"
echo "Region: $region"
echo "Blueprint: $(pwd)"
echo

# Check if terraform directory exists
if [ ! -d "terraform" ]; then
    echo "❌ ERROR: terraform directory not found"
    echo "Are you in the correct blueprint directory?"
    exit 1
fi

cd terraform

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ] && [ ! -f "terraform.tfstate.backup" ]; then
    echo "⚠️  No terraform state found - nothing to cleanup"
    echo "Cleaning local terraform cache anyway..."
    rm -rf .terraform/
    echo "✅ Local cleanup complete"
    exit 0
fi

echo "⚠️  WARNING: This will destroy ALL resources for the Spark K8s Operator blueprint"
echo "Resources that will be destroyed:"
echo "  - EKS Cluster: spark-k8s-operator"
echo "  - VPC and networking"
echo "  - S3 buckets and logs"
echo "  - IAM roles and policies"
echo "  - All associated AWS resources"
echo

read -p "Are you sure you want to proceed? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "❌ Cleanup cancelled"
    exit 0
fi

echo
echo "=== Step 1: Destroy AWS Resources ==="

# Initialize if needed
if [ ! -d ".terraform" ]; then
    echo "🔧 Initializing terraform..."
    terraform init
fi

echo "🧹 Destroying infrastructure..."
if terraform destroy -var="region=$region" -auto-approve; then
    echo "✅ AWS resources destroyed successfully"
else
    echo "⚠️  Some resources may have failed to destroy"
    echo "💡 Check AWS console for any remaining resources"
fi

echo
echo "=== Step 2: Clean Local Cache (Preserving State) ==="
echo "🧹 Cleaning terraform cache (keeping state files)..."
rm -rf .terraform/
echo "⚠️  terraform.tfstate files preserved for future use"

echo
echo "=== Step 3: Manual Cleanup Check ==="
echo "⚠️  Please manually verify these resources are cleaned up in AWS console:"
echo "  - Load Balancers (ELB/ALB/NLB)"
echo "  - Target Groups" 
echo "  - Security Groups (non-default)"
echo "  - EKS cluster: spark-k8s-operator"
echo "  - VPC: spark-k8s-operator*"
echo "  - S3 buckets: spark-k8s-operator-*"
echo

echo "✅ Cleanup Complete!"
echo
echo "💡 To redeploy, run: ./deploy.sh $region"