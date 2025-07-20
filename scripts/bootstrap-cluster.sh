#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
BLUEPRINT_PATH=""
CLUSTER_NAME=""
REGION="us-west-2"
AUTO_APPROVE=false
SKIP_ARGOCD=false

usage() {
    echo "Usage: $0 -b <blueprint-path> -n <cluster-name> [-r <region>] [-y] [-s]"
    echo ""
    echo "Options:"
    echo "  -b, --blueprint     Path to blueprint terraform directory (required)"
    echo "  -n, --name          Cluster name (required)"
    echo "  -r, --region        AWS region (default: us-west-2)"
    echo "  -y, --yes           Auto-approve terraform apply"
    echo "  -s, --skip-argocd   Skip ArgoCD application deployment"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -b infrastructure/blueprints/analytics/spark-k8s-operator/terraform -n my-spark-cluster"
    echo "  $0 -b infrastructure/blueprints/analytics/spark-k8s-operator/terraform -n my-spark-cluster -r us-east-1 -y"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--blueprint)
            BLUEPRINT_PATH="$2"
            shift 2
            ;;
        -n|--name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -y|--yes)
            AUTO_APPROVE=true
            shift
            ;;
        -s|--skip-argocd)
            SKIP_ARGOCD=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$BLUEPRINT_PATH" || -z "$CLUSTER_NAME" ]]; then
    echo -e "${RED}Error: Blueprint path and cluster name are required${NC}"
    usage
    exit 1
fi

# Validate blueprint path exists
if [[ ! -d "$BLUEPRINT_PATH" ]]; then
    echo -e "${RED}Error: Blueprint path '$BLUEPRINT_PATH' does not exist${NC}"
    exit 1
fi

# Validate terraform files exist
if [[ ! -f "$BLUEPRINT_PATH/main.tf" ]]; then
    echo -e "${RED}Error: No main.tf found in '$BLUEPRINT_PATH'${NC}"
    exit 1
fi

echo -e "${GREEN}🚀 Data-on-EKS v2 Cluster Bootstrap${NC}"
echo -e "${YELLOW}===================================${NC}"
echo "Blueprint: $BLUEPRINT_PATH"
echo "Cluster Name: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Auto Approve: $AUTO_APPROVE"
echo "Skip ArgoCD: $SKIP_ARGOCD"
echo ""

# Step 1: Deploy Infrastructure
echo -e "${GREEN}📦 Step 1: Deploying Infrastructure with Terraform${NC}"
cd "$BLUEPRINT_PATH"

# Check if terraform.tfvars exists
if [[ ! -f "terraform.tfvars" ]]; then
    if [[ -f "terraform.tfvars.example" ]]; then
        echo -e "${YELLOW}⚠️  No terraform.tfvars found. Creating from example...${NC}"
        cp terraform.tfvars.example terraform.tfvars
        echo -e "${YELLOW}📝 Please edit terraform.tfvars and run this script again${NC}"
        exit 1
    else
        echo -e "${RED}Error: No terraform.tfvars or terraform.tfvars.example found${NC}"
        exit 1
    fi
fi

# Initialize terraform
echo "🔧 Initializing Terraform..."
terraform init

# Plan terraform
echo "📋 Planning Terraform..."
if [[ "$AUTO_APPROVE" == "true" ]]; then
    terraform plan -out=tfplan
else
    terraform plan
fi

# Apply terraform
echo "🏗️  Applying Terraform..."
if [[ "$AUTO_APPROVE" == "true" ]]; then
    terraform apply tfplan
else
    terraform apply
fi

# Get outputs
echo "📤 Getting Terraform outputs..."
CLUSTER_NAME_OUTPUT=$(terraform output -raw cluster_name)
REGION_OUTPUT=$(terraform output -raw region)
ARGOCD_NAMESPACE=$(terraform output -raw argocd_namespace)

echo -e "${GREEN}✅ Infrastructure deployed successfully!${NC}"

# Step 2: Configure kubectl
echo -e "${GREEN}⚙️  Step 2: Configuring kubectl${NC}"
echo "🔗 Updating kubeconfig..."
aws eks --region "$REGION_OUTPUT" update-kubeconfig --name "$CLUSTER_NAME_OUTPUT"

# Verify connection
echo "🔍 Verifying cluster connection..."
kubectl get nodes

echo -e "${GREEN}✅ kubectl configured successfully!${NC}"

# Step 3: Wait for ArgoCD
if [[ "$SKIP_ARGOCD" == "false" ]]; then
    echo -e "${GREEN}🔄 Step 3: Waiting for ArgoCD to be ready${NC}"
    echo "⏳ Waiting for ArgoCD server to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n "$ARGOCD_NAMESPACE"
    
    echo "🔐 Getting ArgoCD admin password..."
    ARGOCD_PASSWORD=$(kubectl -n "$ARGOCD_NAMESPACE" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    echo -e "${GREEN}✅ ArgoCD is ready!${NC}"
    echo ""
    echo -e "${YELLOW}🎯 ArgoCD Access Information:${NC}"
    echo "Port forward: kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
    echo "URL: https://localhost:8080"
    echo "Username: admin"
    echo "Password: $ARGOCD_PASSWORD"
    echo ""
    
    # Step 4: Deploy Applications
    echo -e "${GREEN}📱 Step 4: Deploying Applications via ArgoCD${NC}"
    
    # Get the blueprint directory relative to repo root
    BLUEPRINT_DIR=$(dirname "$BLUEPRINT_PATH")
    ARGOCD_APPS_DIR="$BLUEPRINT_DIR/argocd-apps"
    
    if [[ -d "$ARGOCD_APPS_DIR" ]]; then
        echo "🚀 Deploying ArgoCD applications from $ARGOCD_APPS_DIR..."
        
        # Apply app-of-apps if it exists
        if [[ -f "$ARGOCD_APPS_DIR/*app-of-apps.yaml" ]]; then
            kubectl apply -f "$ARGOCD_APPS_DIR"/*app-of-apps.yaml
        else
            # Apply individual applications
            kubectl apply -f "$ARGOCD_APPS_DIR"/*.yaml
        fi
        
        echo -e "${GREEN}✅ ArgoCD applications deployed!${NC}"
    else
        echo -e "${YELLOW}⚠️  No ArgoCD applications found in $ARGOCD_APPS_DIR${NC}"
    fi
fi

# Final Summary
echo ""
echo -e "${GREEN}🎉 Bootstrap Complete!${NC}"
echo -e "${YELLOW}===================${NC}"
echo "Cluster Name: $CLUSTER_NAME_OUTPUT"
echo "Region: $REGION_OUTPUT"
echo "kubectl: Configured and ready"
if [[ "$SKIP_ARGOCD" == "false" ]]; then
    echo "ArgoCD: Ready at https://localhost:8080"
fi
echo ""
echo -e "${GREEN}Next Steps:${NC}"
echo "1. Port forward to ArgoCD: kubectl port-forward svc/argocd-server -n $ARGOCD_NAMESPACE 8080:443"
echo "2. Access ArgoCD UI at https://localhost:8080"
echo "3. Deploy your workloads via ArgoCD applications"
echo "4. Monitor with: kubectl get applications -n argocd"
echo ""
echo -e "${GREEN}Happy Data Engineering! 🚀${NC}"