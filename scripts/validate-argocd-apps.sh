#!/bin/bash

set -e

echo "🔍 Validating ArgoCD Applications..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0

# Function to validate YAML syntax
validate_yaml() {
    local file="$1"
    if ! yamllint -q "$file"; then
        echo -e "${RED}❌ YAML syntax error in $file${NC}"
        ((ERRORS++))
        return 1
    fi
    return 0
}

# Function to validate ArgoCD Application spec
validate_argocd_app() {
    local file="$1"
    
    # Check if it's an ArgoCD Application
    if ! grep -q "kind: Application" "$file" && ! grep -q "kind: ApplicationSet" "$file"; then
        return 0  # Skip non-ArgoCD files
    fi
    
    echo "🔍 Validating ArgoCD app: $file"
    
    # Check required fields
    local required_fields=("apiVersion" "kind" "metadata" "spec")
    for field in "${required_fields[@]}"; do
        if ! grep -q "^${field}:" "$file"; then
            echo -e "${RED}❌ Missing required field '$field' in $file${NC}"
            ((ERRORS++))
        fi
    done
    
    # Check source configuration
    if grep -q "kind: Application" "$file"; then
        if ! grep -q "source:" "$file"; then
            echo -e "${RED}❌ Missing 'source' configuration in $file${NC}"
            ((ERRORS++))
        fi
        
        if ! grep -q "destination:" "$file"; then
            echo -e "${RED}❌ Missing 'destination' configuration in $file${NC}"
            ((ERRORS++))
        fi
    fi
    
    # Validate Helm values syntax (basic check)
    if grep -q "values: |" "$file"; then
        local line_num=$(grep -n "values: |" "$file" | cut -d: -f1)
        local values_section=$(tail -n +$((line_num + 1)) "$file")
        
        # Check basic YAML indentation in values
        if echo "$values_section" | grep -E "^[^ ]" | grep -v "^$" | grep -v "^destination:" | grep -v "^syncPolicy:" > /dev/null; then
            echo -e "${YELLOW}⚠️  Potential indentation issue in Helm values for $file${NC}"
        fi
    fi
    
    return 0
}

# Function to validate Karpenter resources
validate_karpenter() {
    local file="$1"
    
    if grep -q "kind: NodePool" "$file" || grep -q "kind: EC2NodeClass" "$file"; then
        echo "🔍 Validating Karpenter resource: $file"
        
        # Check for required Karpenter fields
        if grep -q "kind: NodePool" "$file"; then
            if ! grep -q "nodeClassRef:" "$file"; then
                echo -e "${RED}❌ NodePool missing nodeClassRef in $file${NC}"
                ((ERRORS++))
            fi
        fi
        
        if grep -q "kind: EC2NodeClass" "$file"; then
            if ! grep -q "amiFamily:" "$file"; then
                echo -e "${RED}❌ EC2NodeClass missing amiFamily in $file${NC}"
                ((ERRORS++))
            fi
        fi
    fi
    
    return 0
}

# Main validation loop
find_argocd_files() {
    find . -name "*.yaml" -o -name "*.yml" | grep -E "(argocd-addons|argocd-apps)" | head -20
}

echo "📋 Found ArgoCD files to validate:"
find_argocd_files

echo ""
echo "🔍 Starting validation..."

while IFS= read -r file; do
    if [[ -f "$file" ]]; then
        validate_yaml "$file"
        validate_argocd_app "$file"
        validate_karpenter "$file"
    fi
done < <(find_argocd_files)

# Summary
echo ""
if [[ $ERRORS -eq 0 ]]; then
    echo -e "${GREEN}✅ All ArgoCD applications are valid!${NC}"
    exit 0
else
    echo -e "${RED}❌ Found $ERRORS validation errors${NC}"
    exit 1
fi