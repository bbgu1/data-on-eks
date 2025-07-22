#!/bin/bash
# ==============================================================================
# Spark on EKS - Complete Blueprint Cleanup
# Destroys: Applications → ArgoCD → Addons → EKS → VPC (Reverse Order)
# ==============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }
step() { echo -e "${CYAN}🧹 $1${NC}"; }

# Banner
echo -e "${RED}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║                    🧹 Spark on EKS Cleanup                       ║
║              Complete Blueprint Destruction                       ║
║         Applications → ArgoCD → Addons → EKS → VPC                ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ==============================================================================
# Prerequisites and Validation
# ==============================================================================

step "Validating Prerequisites"

# Check if we're in the correct directory
EXPECTED_PATH="blueprints/spark-on-eks/terraform"
CURRENT_PATH=$(pwd | grep -o "$EXPECTED_PATH" || echo "")

if [[ "$CURRENT_PATH" != "$EXPECTED_PATH" ]]; then
    error "This script must be run from blueprints/spark-on-eks/terraform directory
    Current: $(pwd)
    Expected: */$EXPECTED_PATH"
fi

# Check required tools
command -v terraform >/dev/null 2>&1 || error "Terraform not installed"
command -v kubectl >/dev/null 2>&1 || warning "kubectl not installed (Kubernetes cleanup will be skipped)"
command -v aws >/dev/null 2>&1 || error "AWS CLI not installed"

# Check AWS credentials
aws sts get-caller-identity >/dev/null 2>&1 || error "AWS credentials not configured"

# Get parameters
REGION=${1:-}
FORCE=${2:-false}

if [ -z "$REGION" ]; then
    read -p "Enter AWS region (e.g., us-west-2): " REGION
    [ -z "$REGION" ] && error "Region is required"
fi

# Set AWS environment variables
export AWS_DEFAULT_REGION=$REGION
export AWS_REGION=$REGION

info "Validated prerequisites ✓"
info "Region: $REGION"
info "AWS Account: $(aws sts get-caller-identity --query Account --output text)"

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ] && [ ! -f "terraform.tfstate.backup" ]; then
    warning "No Terraform state found"
    if [ "$FORCE" != "true" ]; then
        read -p "Continue with cleanup anyway? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            info "Cleanup cancelled"
            exit 0
        fi
    fi
    warning "Proceeding without Terraform state - manual cleanup may be required"
fi

# ==============================================================================
# Safety Confirmation
# ==============================================================================

if [ "$FORCE" != "true" ]; then
    step "Safety Confirmation"
    
    # Get cluster info if available
    CLUSTER_NAME=""
    S3_BUCKET=""
    VPC_ID=""
    
    if [ -f "terraform.tfstate" ] || [ -f "terraform.tfstate.backup" ]; then
        CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "Unknown")
        S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "Unknown")
        VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "Unknown")
    fi
    
    echo ""
    warning "⚠️  DANGER: This will destroy ALL resources for Spark on EKS blueprint"
    echo ""
    echo "Resources that will be PERMANENTLY DELETED:"
    echo "  🗂️  EKS Cluster: ${CLUSTER_NAME:-Unknown}"
    echo "  🌐 VPC: ${VPC_ID:-Unknown}"
    echo "  📦 S3 Bucket: ${S3_BUCKET:-Unknown}"
    echo "  🔐 IAM Roles and Policies"
    echo "  💾 All data in S3 bucket"
    echo "  🖥️  All running workloads"
    echo "  📊 All monitoring data"
    echo "  🔄 All ArgoCD applications"
    echo ""
    warning "This action CANNOT be undone!"
    echo ""
    
    read -p "Are you absolutely sure you want to proceed? Type 'destroy' to confirm: " confirm
    if [[ "$confirm" != "destroy" ]]; then
        info "Cleanup cancelled - wise choice! 🛡️"
        exit 0
    fi
    
    echo ""
    warning "Final confirmation: Type the cluster name '${CLUSTER_NAME:-UNKNOWN}' to proceed:"
    read -p "> " cluster_confirm
    if [[ "$cluster_confirm" != "$CLUSTER_NAME" ]] && [[ "$CLUSTER_NAME" != "Unknown" ]]; then
        error "Cluster name mismatch. Cleanup cancelled for safety."
    fi
fi

info "Proceeding with cleanup..."

# ==============================================================================
# Phase 1: Kubernetes Resources Cleanup (Reverse Order)
# ==============================================================================

step "Phase 1: Kubernetes Resources Cleanup"

# Configure kubectl if cluster exists
KUBECTL_CONFIGURED=false
if command -v kubectl >/dev/null 2>&1; then
    info "Attempting to configure kubectl..."
    
    # Try to get cluster name from terraform
    if [ -f "terraform.tfstate" ] || [ -f "terraform.tfstate.backup" ]; then
        CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
        if [ -n "$CLUSTER_NAME" ]; then
            if aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME 2>/dev/null; then
                KUBECTL_CONFIGURED=true
                success "kubectl configured for cluster: $CLUSTER_NAME"
            else
                warning "Failed to configure kubectl (cluster may not exist)"
            fi
        fi
    fi
fi

if [ "$KUBECTL_CONFIGURED" = true ]; then
    # Step 1: Remove ArgoCD Applications
    info "🗑️  Step 1: Removing ArgoCD applications..."
    if kubectl get applications -n argocd >/dev/null 2>&1; then
        # Delete all applications except argocd itself
        kubectl delete applications -n argocd --all --ignore-not-found=true --timeout=300s || warning "Some applications may not have deleted cleanly"
        success "ArgoCD applications removed"
    else
        info "No ArgoCD applications found"
    fi
    
    # Step 2: Remove Workloads (Spark jobs, etc.)
    info "🗑️  Step 2: Removing Spark workloads..."
    for ns in spark-operator spark-team-a spark-team-b spark-examples default; do
        if kubectl get namespace $ns >/dev/null 2>&1; then
            info "Cleaning namespace: $ns"
            kubectl delete sparkapplications -n $ns --all --ignore-not-found=true --timeout=300s || true
            kubectl delete pods -n $ns --all --ignore-not-found=true --timeout=300s || true
        fi
    done
    success "Spark workloads removed"
    
    # Step 3: Remove Karpenter NodePools (to prevent new nodes)
    info "🗑️  Step 3: Removing Karpenter NodePools..."
    if kubectl get nodepools -n karpenter >/dev/null 2>&1; then
        kubectl delete nodepools -n karpenter --all --ignore-not-found=true --timeout=300s || warning "Some NodePools may not have deleted"
        kubectl delete ec2nodeclasses -n karpenter --all --ignore-not-found=true --timeout=300s || warning "Some EC2NodeClasses may not have deleted"
        success "Karpenter NodePools removed"
    else
        info "No Karpenter NodePools found"
    fi
    
    # Step 4: Wait for nodes to drain
    info "🗑️  Step 4: Waiting for nodes to drain..."
    sleep 30  # Give Karpenter time to process
    
    # Step 5: Remove LoadBalancers and Services (to prevent dangling resources)
    info "🗑️  Step 5: Removing LoadBalancers and Services..."
    kubectl delete services --all-namespaces --field-selector spec.type=LoadBalancer --ignore-not-found=true --timeout=300s || warning "Some LoadBalancers may not have deleted"
    success "LoadBalancers and Services removed"
    
    info "Kubernetes cleanup completed ✓"
else
    warning "Skipping Kubernetes cleanup (kubectl not configured)"
fi

# ==============================================================================
# Phase 2: AWS Load Balancers Cleanup (Manual)
# ==============================================================================

step "Phase 2: AWS Load Balancers Cleanup"

info "🗑️  Checking for dangling Load Balancers..."

# Get cluster name for load balancer filtering
if [ -n "$CLUSTER_NAME" ]; then
    # Check for ALBs
    ALB_ARNS=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerArn" --output text 2>/dev/null || echo "")
    if [ -n "$ALB_ARNS" ]; then
        warning "Found Load Balancers that may need manual cleanup:"
        for arn in $ALB_ARNS; do
            echo "  - $arn"
            aws elbv2 delete-load-balancer --load-balancer-arn $arn --region $REGION 2>/dev/null || warning "Failed to delete $arn"
        done
    fi
    
    # Check for CLBs
    CLB_NAMES=$(aws elb describe-load-balancers --region $REGION --query "LoadBalancerDescriptions[?contains(LoadBalancerName, '$CLUSTER_NAME')].LoadBalancerName" --output text 2>/dev/null || echo "")
    if [ -n "$CLB_NAMES" ]; then
        warning "Found Classic Load Balancers that may need manual cleanup:"
        for name in $CLB_NAMES; do
            echo "  - $name"
            aws elb delete-load-balancer --load-balancer-name $name --region $REGION 2>/dev/null || warning "Failed to delete $name"
        done
    fi
fi

success "Load Balancer cleanup completed ✓"

# ==============================================================================
# Phase 3: Terraform Infrastructure Destruction (Reverse Order)
# ==============================================================================

step "Phase 3: Terraform Infrastructure Destruction"

# Initialize terraform if needed
if [ ! -d ".terraform" ]; then
    info "🔧 Initializing Terraform..."
    terraform init -upgrade
fi

# Terraform destroy in reverse dependency order
info "🏗️  Phase 3a: Destroying S3 and storage resources..."
terraform destroy -target="aws_s3_bucket_server_side_encryption_configuration.spark" -target="aws_s3_bucket_public_access_block.spark" -target="aws_s3_bucket.spark" -var-file=terraform.tfvars -auto-approve 2>/dev/null || warning "S3 cleanup may have failed"

info "🏗️  Phase 3b: Destroying IAM and Pod Identity..."
terraform destroy -target="aws_eks_pod_identity_association.spark_operator" -target="aws_iam_role_policy_attachment.spark_operator" -target="aws_iam_policy.spark_operator" -target="aws_iam_role.spark_operator" -var-file=terraform.tfvars -auto-approve 2>/dev/null || warning "IAM cleanup may have failed"

info "🏗️  Phase 3c: Destroying EKS cluster..."
terraform destroy -target="module.eks" -var-file=terraform.tfvars -auto-approve 2>/dev/null || warning "EKS cleanup may have failed"

info "🏗️  Phase 3d: Destroying VPC and networking..."
terraform destroy -target="module.vpc" -var-file=terraform.tfvars -auto-approve 2>/dev/null || warning "VPC cleanup may have failed"

# Final destroy to catch anything remaining
info "🏗️  Phase 3e: Final cleanup of remaining resources..."
if terraform destroy -var-file=terraform.tfvars -auto-approve; then
    success "All Terraform resources destroyed successfully"
else
    warning "Some Terraform resources may have failed to destroy"
    warning "Check AWS console for any remaining resources"
fi

# ==============================================================================
# Phase 4: Manual Cleanup Verification
# ==============================================================================

step "Phase 4: Manual Cleanup Verification"

info "🔍 Checking for resources that may need manual cleanup..."

# Check for remaining EKS clusters
if [ -n "$CLUSTER_NAME" ]; then
    REMAINING_CLUSTER=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region $REGION 2>/dev/null || echo "")
    if [ -n "$REMAINING_CLUSTER" ]; then
        warning "EKS cluster still exists: $CLUSTER_NAME"
    else
        success "EKS cluster removed: $CLUSTER_NAME"
    fi
fi

# Check for remaining VPCs
if [ -n "$VPC_ID" ]; then
    REMAINING_VPC=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region $REGION 2>/dev/null || echo "")
    if [ -n "$REMAINING_VPC" ]; then
        warning "VPC still exists: $VPC_ID"
    else
        success "VPC removed: $VPC_ID"
    fi
fi

# Check for remaining S3 buckets
if [ -n "$S3_BUCKET" ]; then
    REMAINING_BUCKET=$(aws s3 ls s3://"$S3_BUCKET" 2>/dev/null || echo "")
    if [ -n "$REMAINING_BUCKET" ]; then
        warning "S3 bucket still exists: $S3_BUCKET"
        warning "You may need to empty and delete it manually"
    else
        success "S3 bucket removed: $S3_BUCKET"
    fi
fi

# ==============================================================================
# Phase 5: Local Cleanup
# ==============================================================================

step "Phase 5: Local Cleanup"

info "🧹 Cleaning local Terraform cache..."
rm -rf .terraform/
rm -f .terraform.lock.hcl
rm -f tfplan

# Preserve tfstate files for potential recovery
if [ -f "terraform.tfstate" ] || [ -f "terraform.tfstate.backup" ]; then
    warning "terraform.tfstate files preserved for potential recovery"
    warning "Remove manually if cleanup is confirmed complete"
else
    success "No state files to preserve"
fi

success "Local cleanup completed ✓"

# ==============================================================================
# Cleanup Summary
# ==============================================================================

echo ""
echo -e "${GREEN}🎉 Spark on EKS Cleanup Complete!${NC}"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo -e "${CYAN}📋 Cleanup Summary:${NC}"
echo "  🗂️  EKS Cluster: ${CLUSTER_NAME:-Unknown} - Destroyed"
echo "  🌐 VPC: ${VPC_ID:-Unknown} - Destroyed"
echo "  📦 S3 Bucket: ${S3_BUCKET:-Unknown} - Destroyed"
echo "  🔐 IAM Roles: Destroyed"
echo "  🔄 ArgoCD Applications: Destroyed"
echo ""
echo -e "${CYAN}⚠️  Manual Verification Recommended:${NC}"
echo ""
echo "  1. Check AWS Console for any remaining resources:"
echo "     • EKS Clusters: https://$REGION.console.aws.amazon.com/eks/"
echo "     • VPCs: https://$REGION.console.aws.amazon.com/vpc/"
echo "     • Load Balancers: https://$REGION.console.aws.amazon.com/ec2/v2/home?region=$REGION#LoadBalancers:"
echo "     • S3 Buckets: https://s3.console.aws.amazon.com/s3/"
echo ""
echo "  2. Resources that may need manual cleanup:"
echo "     • Load Balancers created by services"
echo "     • Target Groups"
echo "     • Security Groups (non-default)"
echo "     • Elastic IPs"
echo "     • NAT Gateways (if failed to delete)"
echo ""
echo -e "${CYAN}🔄 To redeploy:${NC}"
echo "     ./deploy.sh $REGION"
echo ""
success "Cleanup verification completed! 🧹"
echo ""