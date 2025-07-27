#!/bin/bash
# ==============================================================================
# Spark on EKS - Complete Blueprint Deployment
# Deploys: VPC → EKS → ArgoCD → Addons → Applications
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
step() { echo -e "${CYAN}🚀 $1${NC}"; }

# Banner
echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║                    🚀 Spark on EKS v2.0                          ║
║              Complete Blueprint Deployment                        ║
║         VPC → EKS → ArgoCD → Addons → Applications                ║
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
command -v kubectl >/dev/null 2>&1 || error "kubectl not installed"
command -v aws >/dev/null 2>&1 || error "AWS CLI not installed"

# Check AWS credentials
aws sts get-caller-identity >/dev/null 2>&1 || error "AWS credentials not configured"

# Get parameters
REGION=${1:-}
ENVIRONMENT=${2:-"dev"}

if [ -z "$REGION" ]; then
    read -p "Enter AWS region (e.g., us-west-2): " REGION
    [ -z "$REGION" ] && error "Region is required"
fi

# Validate region format
if [[ ! "$REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]]; then
    error "Invalid region format. Use format like: us-west-2, eu-west-1"
fi

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
    error "Environment must be: dev, staging, or prod"
fi

# Set AWS environment variables
export AWS_DEFAULT_REGION=$REGION
export AWS_REGION=$REGION

info "Validated prerequisites ✓"
info "Region: $REGION"
info "Environment: $ENVIRONMENT"
info "AWS Account: $(aws sts get-caller-identity --query Account --output text)"

# ==============================================================================
# Terraform Configuration
# ==============================================================================

step "Configuring Terraform"

# Initialize terraform
info "Initializing Terraform..."
terraform init -upgrade

# Create terraform.tfvars if it doesn't exist
if [ ! -f "terraform.tfvars" ]; then
    warning "Creating default terraform.tfvars file"
    cat > terraform.tfvars << EOF
# Spark on EKS Blueprint Configuration
name        = "spark-on-eks"
region      = "$REGION"
environment = "$ENVIRONMENT"

# EKS Configuration
eks_cluster_version = "1.33"
cluster_endpoint_public_access = true

# Networking
vpc_cidr = "10.0.0.0/16"
secondary_cidrs = ["100.64.0.0/16"]

# Tags
tags = {
  Blueprint   = "spark-on-eks"
  Environment = "$ENVIRONMENT"
  ManagedBy   = "terraform"
  Owner       = "$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)"
  CreatedBy   = "deploy-script"
  Region      = "$REGION"
}
EOF
    success "Created terraform.tfvars with default values"
fi

# Terraform planning
info "Planning Terraform deployment..."
terraform plan -var-file=terraform.tfvars -out=tfplan

success "Terraform configuration ready ✓"

# ==============================================================================
# Infrastructure Deployment (Ordered Dependencies)
# ==============================================================================

step "Deploying Infrastructure (Phase 1: Foundations)"

# Phase 1: VPC and Networking
info "🏗️  Phase 1: Deploying VPC and networking..."
if terraform apply -target="module.vpc" -var-file=terraform.tfvars -auto-approve; then
    success "VPC deployed successfully"
else
    error "VPC deployment failed"
fi

# Wait a moment for VPC propagation
sleep 10

# Phase 2: EKS Cluster
info "🏗️  Phase 2: Deploying EKS cluster..."
if terraform apply -target="module.eks" -var-file=terraform.tfvars -auto-approve; then
    success "EKS cluster deployed successfully"
else
    error "EKS cluster deployment failed"
fi

# Phase 3: IAM and Pod Identity
info "🏗️  Phase 3: Deploying IAM roles and Pod Identity..."
if terraform apply -target="aws_iam_role.spark_operator" -target="aws_iam_policy.spark_operator" -target="aws_eks_pod_identity_association.spark_operator" -var-file=terraform.tfvars -auto-approve; then
    success "IAM and Pod Identity deployed successfully"
else
    error "IAM deployment failed"
fi

# Phase 4: S3 and Storage
info "🏗️  Phase 4: Deploying S3 bucket and storage..."
if terraform apply -target="aws_s3_bucket.spark" -target="aws_s3_bucket_public_access_block.spark" -target="aws_s3_bucket_server_side_encryption_configuration.spark" -var-file=terraform.tfvars -auto-approve; then
    success "S3 storage deployed successfully"
else
    error "S3 deployment failed"
fi

# Phase 5: Final apply for any remaining resources
info "🏗️  Phase 5: Applying remaining resources..."
if terraform apply -var-file=terraform.tfvars -auto-approve; then
    success "All infrastructure deployed successfully"
else
    error "Final infrastructure deployment failed"
fi

# ==============================================================================
# Kubernetes Configuration
# ==============================================================================

step "Configuring Kubernetes Access"

# Get cluster details
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null) || error "Failed to get cluster name from Terraform output"
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null) || error "Failed to get S3 bucket from Terraform output"

info "Cluster Name: $CLUSTER_NAME"
info "S3 Bucket: $S3_BUCKET"

# Configure kubectl
info "Configuring kubectl access..."
if aws eks --region $REGION update-kubeconfig --name $CLUSTER_NAME; then
    success "kubectl configured successfully"
else
    error "Failed to configure kubectl"
fi

# Wait for cluster to be ready
info "⏳ Waiting for cluster to be ready (this may take 5-10 minutes)..."
kubectl wait --for=condition=Ready nodes --all --timeout=600s || warning "Some nodes may still be initializing"

# Verify cluster access
info "Verifying cluster access..."
kubectl get nodes || error "Cannot access cluster nodes"
kubectl get namespaces || error "Cannot access cluster namespaces"

success "Kubernetes access configured ✓"

# ==============================================================================
# ArgoCD Applications Deployment
# ==============================================================================

step "Deploying ArgoCD Applications"

# Check if ArgoCD is available
info "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s || warning "ArgoCD may still be starting"

# Deploy composition (App of Apps) with dynamic values
info "🎯 Deploying Spark blueprint composition..."

# Get repo root path for local filesystem
REPO_ROOT=$(cd .. && cd .. && pwd)

# Create temporary composition with actual values
TEMP_COMPOSITION=$(mktemp)
sed -e "s|file://LOCAL_REPO_PATH|file://$REPO_ROOT|g" \
    -e "s|CLUSTER_NAME_PLACEHOLDER|$CLUSTER_NAME|g" \
    -e "s|REGION_PLACEHOLDER|$REGION|g" \
    -e "s|S3_BUCKET_PLACEHOLDER|$S3_BUCKET|g" \
    ../composition.yaml > "$TEMP_COMPOSITION"

if kubectl apply -f "$TEMP_COMPOSITION"; then
    success "Blueprint composition deployed with cluster-specific values"
    rm "$TEMP_COMPOSITION"
else
    error "Failed to deploy blueprint composition"
fi

# Wait for applications to sync
info "⏳ Waiting for ArgoCD applications to sync (5-10 minutes)..."
sleep 60  # Give ArgoCD time to process

# Monitor application health
TIMEOUT=600
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check if applications exist
    APP_COUNT=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l || echo "0")

    if [ "$APP_COUNT" -gt 0 ]; then
        info "Found $APP_COUNT ArgoCD applications"

        # Check application health
        HEALTHY_COUNT=$(kubectl get applications -n argocd -o jsonpath='{.items[?(@.status.health.status=="Healthy")].metadata.name}' 2>/dev/null | wc -w || echo "0")

        if [ "$HEALTHY_COUNT" -eq "$APP_COUNT" ] && [ "$APP_COUNT" -gt 0 ]; then
            success "All ArgoCD applications are healthy!"
            break
        else
            info "Applications status: $HEALTHY_COUNT/$APP_COUNT healthy (waiting...)"
        fi
    else
        info "Waiting for ArgoCD applications to appear..."
    fi

    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    warning "Deployment timeout reached. Applications may still be syncing."
    warning "Check ArgoCD UI for detailed status."
fi

# ==============================================================================
# Verification and Summary
# ==============================================================================

step "Verifying Deployment"

# Check Karpenter
info "Checking Karpenter..."
if kubectl get deployment karpenter -n karpenter >/dev/null 2>&1; then
    KARPENTER_STATUS=$(kubectl get deployment karpenter -n karpenter -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$KARPENTER_STATUS" -gt 0 ]; then
        success "Karpenter is running ($KARPENTER_STATUS replicas)"
    else
        warning "Karpenter is deployed but not ready yet"
    fi
else
    warning "Karpenter not found (may still be deploying)"
fi

# Check Spark Operator
info "Checking Spark Operator..."
if kubectl get deployment spark-operator -n spark-operator >/dev/null 2>&1; then
    SPARK_STATUS=$(kubectl get deployment spark-operator -n spark-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [ "$SPARK_STATUS" -gt 0 ]; then
        success "Spark Operator is running ($SPARK_STATUS replicas)"
    else
        warning "Spark Operator is deployed but not ready yet"
    fi
else
    warning "Spark Operator not found (may still be deploying)"
fi

# Check NodePools
info "Checking Karpenter NodePools..."
NODEPOOL_COUNT=$(kubectl get nodepools -n karpenter --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$NODEPOOL_COUNT" -gt 0 ]; then
    success "Found $NODEPOOL_COUNT Karpenter NodePools"
    kubectl get nodepools -n karpenter 2>/dev/null || true
else
    warning "No NodePools found yet (may still be deploying)"
fi

success "Deployment verification completed ✓"

# ==============================================================================
# Deployment Summary
# ==============================================================================

echo ""
echo -e "${GREEN}🎉 Spark on EKS Deployment Complete!${NC}"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo -e "${CYAN}📋 Deployment Summary:${NC}"
echo "  • Cluster: $CLUSTER_NAME"
echo "  • Region: $REGION"
echo "  • Environment: $ENVIRONMENT"
echo "  • S3 Bucket: $S3_BUCKET"
echo "  • VPC: $(terraform output -raw vpc_id 2>/dev/null || echo 'N/A')"
echo ""
echo -e "${CYAN}🔧 Next Steps:${NC}"
echo ""
echo "  1. Monitor ArgoCD Applications:"
echo "     kubectl get applications -n argocd"
echo ""
echo "  2. Access ArgoCD UI:"
echo "     kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "     Username: admin"
echo "     Password: \$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo ""
echo "  3. Check Karpenter NodePools:"
echo "     kubectl get nodepools -n karpenter"
echo "     kubectl get ec2nodeclasses -n karpenter"
echo ""
echo "  4. Submit a test Spark job:"
echo "     kubectl apply -f ../examples/basic/pyspark-pi.yaml"
echo ""
echo "  5. Monitor cluster nodes:"
echo "     kubectl get nodes --show-labels"
echo ""
echo -e "${CYAN}🌐 Useful URLs:${NC}"
echo "  • ArgoCD UI: http://localhost:8080 (after port-forward)"
echo "  • AWS Console: https://$REGION.console.aws.amazon.com/eks/home?region=$REGION#/clusters/$CLUSTER_NAME"
echo ""
success "Happy Sparking! 🚀"
echo ""
