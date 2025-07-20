#!/bin/bash

set -e

echo "=== DoEKS v2.0 - Cleanup Failed Deployment ==="
echo

# Check if region is provided
if [ -z "$1" ]; then
  read -p "Enter the AWS region (default: us-west-2): " region
  region=${region:-us-west-2}
else
  region=$1
fi

# Set AWS region environment variables
export AWS_DEFAULT_REGION=$region
export AWS_REGION=$region

echo "Using AWS region: $region"
echo

# Navigate to terraform directory
cd terraform

echo "=== Step 1: Destroy Failed Infrastructure ==="
echo "This will clean up all AWS resources created by the failed deployment."
echo
read -p "Proceed with cleanup? (y/N): " proceed
if [[ ! $proceed =~ ^[Yy]$ ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo "Destroying infrastructure..."
terraform destroy -var="region=$region" -auto-approve

echo
echo "=== Step 2: Clean Terraform State ==="
rm -rf .terraform/
rm -f .terraform.lock.hcl
rm -f terraform.tfstate*

echo
echo "=== Cleanup Complete ==="
echo "✅ All resources have been destroyed"
echo "✅ Terraform state has been cleaned"
echo
echo "You can now run ./bootstrap.sh to redeploy with the fixed configuration."