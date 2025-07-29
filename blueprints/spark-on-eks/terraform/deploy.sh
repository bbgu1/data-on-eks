#!/bin/bash
# ==============================================================================
# Spark on EKS - Complete Blueprint Deployment with Gitea
# Deploys: VPC → EKS → Gitea → ArgoCD → Applications → Setup
# ==============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REGION="${1:-}"
readonly ENV="${2:-dev}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper functions
log() { echo "[$(date '+%H:%M:%S')] $*"; }
error() { echo -e "${RED}[ERROR] $*${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}✅ $*${NC}"; }
info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $*${NC}"; }
step() { echo -e "${CYAN}🚀 $*${NC}"; }

# Validation and setup
validate_prerequisites() {
    [[ -n "$REGION" ]] || { echo "Usage: $0 <region> [environment]"; exit 1; }
    [[ "$REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]] || { echo "Invalid region format"; exit 1; }
    [[ "$ENV" =~ ^(dev|staging|prod)$ ]] || { echo "Environment must be: dev, staging, or prod"; exit 1; }
    
    local tools=(terraform kubectl aws curl git)
    for tool in "${tools[@]}"; do
        command -v "$tool" >/dev/null || { echo "Missing required tool: $tool"; exit 1; }
    done
    
    aws sts get-caller-identity >/dev/null || { echo "AWS credentials not configured"; exit 1; }
    export AWS_DEFAULT_REGION="$REGION" AWS_REGION="$REGION"
}

# Banner
echo -e "${BLUE}"
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║                    🚀 Spark on EKS v2.0                          ║
║         Complete Blueprint Deployment with Gitea GitOps          ║
║    VPC → EKS → Gitea → ArgoCD → Applications → Port-Forwards     ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ==============================================================================
# Main Deployment Function
# ==============================================================================

main() {
    validate_prerequisites
    
    log "🚀 Starting Spark on EKS deployment - Region: $REGION, Environment: $ENV"
    
    # ==============================================================================
    # Terraform Deployment
    # ==============================================================================
    
    step "📦 Terraform Deployment"
    
    log "Initializing Terraform"
    terraform init -upgrade -input=false
    
    # Create terraform.tfvars if it doesn't exist
    if [ ! -f "terraform.tfvars" ]; then
        warning "Creating default terraform.tfvars file"
        cat > terraform.tfvars << EOF
# Spark on EKS Blueprint Configuration
name        = "spark-on-eks"
region      = "$REGION"
environment = "$ENV"

# EKS Configuration
eks_cluster_version = "1.33"
cluster_endpoint_public_access = true

# Networking
vpc_cidr = "10.0.0.0/16"
secondary_cidrs = ["100.64.0.0/16"]

# Tags
tags = {
  Blueprint   = "spark-on-eks"
  Environment = "$ENV"
  ManagedBy   = "terraform"
  Owner       = "$(aws sts get-caller-identity --query 'Arn' --output text | cut -d'/' -f2)"
  CreatedBy   = "deploy-script"
  Region      = "$REGION"
}
EOF
        success "Created terraform.tfvars with default values"
    fi
    
    # Phased deployment
    terraform_deploy_phase "module.vpc_blueprint" "VPC and Networking"
    terraform_deploy_phase "module.eks_blueprint" "EKS Cluster"
    terraform_deploy_phase "" "Complete Infrastructure (including Gitea & ArgoCD)"
    
    # ==============================================================================
    # Kubernetes Setup
    # ==============================================================================
    
    step "⚙️  Kubernetes Configuration"
    
    # Get cluster details
    local cluster_name s3_bucket vpc_id
    cluster_name=$(terraform output -raw cluster_name) || error "Failed to get cluster name"
    s3_bucket=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "N/A")
    vpc_id=$(terraform output -raw vpc_id 2>/dev/null || echo "N/A")
    
    log "Configuring kubectl for cluster: $cluster_name"
    aws eks update-kubeconfig --region "$REGION" --name "$cluster_name" --alias "$cluster_name"
    
    log "Waiting for cluster nodes to be ready"
    kubectl wait --for=condition=Ready nodes --all --timeout=600s || warning "Some nodes may still be initializing"
    
    success "Kubernetes access configured ✓"
    
    # ==============================================================================
    # Gitea Setup
    # ==============================================================================
    
    step "🐙 Gitea Repository Setup"
    
    log "Waiting for Gitea to be ready"
    kubectl wait --for=condition=available deployment/gitea -n gitea --timeout=300s || error "Gitea deployment failed"
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=gitea -n gitea --timeout=300s || error "Gitea pod failed"
    
    # Get Gitea credentials
    log "Getting Gitea admin credentials from Kubernetes secret"
    local gitea_user gitea_pass
    gitea_user=$(kubectl get secret gitea-admin-secret -n gitea -o jsonpath='{.data.username}' | base64 -d)
    gitea_pass=$(kubectl get secret gitea-admin-secret -n gitea -o jsonpath='{.data.password}' | base64 -d)
    [[ -n "$gitea_user" && -n "$gitea_pass" ]] || error "Failed to get Gitea credentials"
    
    # Setup port-forward for Gitea
    log "Setting up Gitea port-forward"
    pkill -f "kubectl.*port-forward.*gitea" 2>/dev/null || true
    sleep 2
    kubectl port-forward svc/gitea-http -n gitea 3000:3000 >/dev/null 2>&1 &
    local gitea_pid=$!
    
    # Wait for Gitea to be accessible
    log "Waiting for Gitea to be accessible"
    for i in {1..30}; do
        if curl -sf http://localhost:3000/api/v1/version >/dev/null 2>&1; then
            log "Gitea is accessible"
            break
        fi
        [[ $i -eq 30 ]] && { kill "$gitea_pid" 2>/dev/null || true; error "Gitea not accessible after 30 attempts"; }
        sleep 2
    done
    
    # Create repository in Gitea
    log "Creating Gitea repository"
    curl -sf -X POST -H "Content-Type: application/json" -u "$gitea_user:$gitea_pass" \
        -d '{"name":"data-on-eks","description":"Data on EKS local repo","private":false,"auto_init":false}' \
        http://localhost:3000/api/v1/user/repos >/dev/null || log "Repository may already exist"
    
    # Push repository to Gitea
    log "Pushing repository to Gitea"
    cd "$SCRIPT_DIR/../../../"
    git remote remove gitea 2>/dev/null || true
    git remote add gitea "http://$gitea_user:$gitea_pass@localhost:3000/$gitea_user/data-on-eks.git"
    git push gitea HEAD:main --force || log "Push may have failed, continuing"
    cd "$SCRIPT_DIR"
    
    kill "$gitea_pid" 2>/dev/null || true
    success "Gitea repository setup completed ✓"
    
    # ==============================================================================
    # ArgoCD Applications Deployment
    # ==============================================================================
    
    step "🎯 ArgoCD Applications Deployment"
    
    log "Waiting for ArgoCD to be ready"
    kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s || error "ArgoCD deployment failed"
    
    # Update composition.yaml with actual values from Terraform
    log "Updating composition.yaml with actual cluster values"
    local temp_composition=$(mktemp)
    
    # Get additional Terraform outputs
    local karpenter_sqs_queue karpenter_node_profile
    karpenter_sqs_queue=$(terraform output -raw karpenter_sqs_queue_name 2>/dev/null || echo "")
    karpenter_node_profile=$(terraform output -raw karpenter_node_instance_profile 2>/dev/null || echo "")
    
    # Replace all placeholders with actual values
    sed -e "s|CLUSTER_NAME_PLACEHOLDER|$cluster_name|g" \
        -e "s|REGION_PLACEHOLDER|$REGION|g" \
        -e "s|S3_BUCKET_PLACEHOLDER|$s3_bucket|g" \
        -e "s|KARPENTER_SQS_PLACEHOLDER|$karpenter_sqs_queue|g" \
        -e "s|KARPENTER_NODE_PROFILE_PLACEHOLDER|$karpenter_node_profile|g" \
        ../composition.yaml > "$temp_composition"
    
    # Deploy teams application via Terraform
    log "Deploying teams ArgoCD application via Terraform"
    terraform apply -target="kubectl_manifest.spark_teams_argocd_app" -var-file=terraform.tfvars -auto-approve || warning "Teams terraform apply may have failed"
    
    # Deploy composition
    log "Deploying ArgoCD composition"
    kubectl apply -f "$temp_composition" || error "Failed to deploy composition"
    rm "$temp_composition"
    
    # Wait for applications to sync
    log "Waiting for ArgoCD applications to sync"
    local timeout=20
    for i in $(seq 1 $timeout); do
        local app_count healthy_count
        app_count=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
        healthy_count=$(kubectl get applications -n argocd -o jsonpath='{.items[?(@.status.health.status=="Healthy")].metadata.name}' 2>/dev/null | wc -w)
        
        if [[ $app_count -gt 0 && $healthy_count -eq $app_count ]]; then
            log "All $app_count ArgoCD applications are healthy"
            break
        fi
        
        [[ $i -eq $timeout ]] && warning "Not all applications are healthy yet"
        log "Applications status: $healthy_count/$app_count healthy (attempt $i/$timeout)"
        sleep 30
    done
    
    success "ArgoCD applications deployed ✓"
    
    # ==============================================================================
    # Setup Access
    # ==============================================================================
    
    step "🌐 Setting up Access"
    
    # Get ArgoCD password
    log "Getting ArgoCD admin password"
    local argocd_pass
    argocd_pass=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d 2>/dev/null || echo "")
    [[ -n "$argocd_pass" ]] || warning "Failed to retrieve ArgoCD admin password"
    
    # Kill existing port-forwards
    pkill -f "kubectl.*port-forward.*(gitea|argocd)" 2>/dev/null || true
    sleep 2
    
    # Start port-forwards
    kubectl port-forward svc/gitea-http -n gitea 3000:3000 >/dev/null 2>&1 &
    local gitea_pf_pid=$!
    
    kubectl port-forward svc/argocd-server -n argocd 8080:443 >/dev/null 2>&1 &
    local argocd_pf_pid=$!
    
    sleep 3
    
    # ==============================================================================
    # Deployment Summary
    # ==============================================================================
    
    echo ""
    echo -e "${GREEN}🎉 Spark on EKS Deployment Complete with GitOps Setup!${NC}"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo -e "${CYAN}📋 Infrastructure:${NC}"
    echo "  • Cluster: $cluster_name"
    echo "  • Region: $REGION"
    echo "  • Environment: $ENV"
    echo "  • VPC: $vpc_id"
    echo "  • S3 Bucket: $s3_bucket"
    echo ""
    echo -e "${CYAN}🌐 Access Information:${NC}"
    echo "  • Gitea:  http://localhost:3000 ($gitea_user / $gitea_pass)"
    echo "  • ArgoCD: https://localhost:8080 (admin / $argocd_pass)"
    echo ""
    echo -e "${CYAN}🔧 Management Commands:${NC}"
    echo "  kubectl get applications -n argocd"
    echo "  kubectl get nodepools -n karpenter"
    echo "  kubectl get pods -n spark-operator"
    echo ""
    echo -e "${CYAN}🔄 Port-forward PIDs: $gitea_pf_pid $argocd_pf_pid${NC}"
    echo "   Stop with: kill $gitea_pf_pid $argocd_pf_pid"
    echo ""
    success "✅ Deployment completed successfully!"
}

# Terraform deployment helper
terraform_deploy_phase() {
    local target="$1" description="$2"
    log "🏗️  Deploying: $description"
    
    if [[ -n "$target" ]]; then
        terraform apply -target="$target" -var-file=terraform.tfvars -auto-approve
    else
        terraform apply -var-file=terraform.tfvars -auto-approve
    fi
}

# Execute main function
main "$@"