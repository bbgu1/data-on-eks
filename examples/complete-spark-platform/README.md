# Complete Spark Platform Example

This example demonstrates how to deploy a complete Spark analytics platform using the new Data-on-EKS v2 architecture.

## Quick Start

### 1. Deploy with Bootstrap Script

```bash
# Clone the repository
git clone https://github.com/awslabs/data-on-eks.git
cd data-on-eks

# Run the bootstrap script
./scripts/bootstrap-cluster.sh \
  -b infrastructure/blueprints/analytics/spark-k8s-operator/terraform \
  -n my-spark-cluster \
  -r us-west-2 \
  -y
```

### 2. Access Services

```bash
# ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080

# Spark History Server
kubectl port-forward svc/spark-history-server -n spark-history-server 18080:80
# Open http://localhost:18080

# Grafana Dashboards
kubectl port-forward svc/kube-prometheus-stack-grafana -n kube-prometheus-stack 3000:80
# Open http://localhost:3000
```

### 3. Submit Your First Spark Job

```bash
kubectl apply -f - <<EOF
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: pyspark-pi
  namespace: default
spec:
  type: Python
  pythonVersion: "3"
  mode: cluster
  image: "public.ecr.aws/data-on-eks/spark:3.5.3"
  imagePullPolicy: Always
  mainApplicationFile: local:///opt/spark/examples/src/main/python/pi.py
  arguments:
    - "20"
  sparkVersion: "3.5.3"
  restartPolicy:
    type: Never
  driver:
    cores: 1
    coreLimit: "1200m"
    memory: "512m"
    labels:
      version: 3.5.3
    serviceAccount: spark
  executor:
    cores: 1
    instances: 2
    memory: "512m"
    labels:
      version: 3.5.3
EOF
```

## What's Included

- ✅ **EKS Cluster** with optimized configuration
- ✅ **Spark Operator** for Kubernetes-native job management
- ✅ **Karpenter** for auto-scaling compute resources
- ✅ **ArgoCD** for GitOps workflow management
- ✅ **Monitoring Stack** (Prometheus + Grafana)
- ✅ **Spark History Server** for job monitoring
- ✅ **Cost Management** with Kubecost
- ✅ **Logging** with AWS for Fluent Bit

## Architecture Highlights

### New v2 Benefits

- **70-80% less duplicate code** compared to v1
- **Pure GitOps**: All K8s resources via ArgoCD
- **Modular Design**: Reusable infrastructure components
- **Easy Maintenance**: Centralized upgrades and configuration

### Resource Optimization

- **Spot Instances**: Cost-optimized with EC2 Spot
- **Auto-Scaling**: Dynamic node provisioning with Karpenter
- **Multi-Architecture**: Support for x86 and Graviton instances

## Monitoring & Observability

### Grafana Dashboards
- Spark application metrics
- Cluster resource utilization
- Cost breakdown by workload

### Prometheus Metrics
- Spark Operator metrics
- Karpenter scaling events
- Application performance

### Cost Optimization
- Kubecost for workload cost attribution
- Spot instance usage tracking
- Resource efficiency recommendations

## Production Considerations

### Security
- IRSA for service account permissions
- Network isolation with private subnets
- Encryption at rest and in transit

### Reliability
- Multi-AZ deployment
- Auto-healing with Kubernetes
- Backup and disaster recovery

### Scalability
- Horizontal pod autoscaling
- Cluster autoscaling with Karpenter
- Load balancing for high availability

## Next Steps

1. **Customize Configuration**: Modify `terraform.tfvars` for your environment
2. **Add Your Data**: Configure S3 buckets and data sources
3. **Deploy Workloads**: Create ArgoCD applications for your jobs
4. **Set Up CI/CD**: Integrate with your GitOps workflow
5. **Monitor & Optimize**: Use dashboards for performance tuning

## Support

- [Documentation](https://awslabs.github.io/data-on-eks/)
- [GitHub Issues](https://github.com/awslabs/data-on-eks/issues)
- [Community Discussions](https://github.com/awslabs/data-on-eks/discussions)