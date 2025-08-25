# Karpenter NodePool Resources

This directory contains **generic, flexible NodePool configurations** that support different workload types. Pods can select the appropriate NodePool using labels and nodeSelector.

## 🏗️ **Available NodePools**

### 1. **compute-optimized-x86** 
- **Purpose**: CPU-intensive x86 workloads
- **Instance Families**: c5, c5d, c5n, c6a, c6i, c6id, c6in, c7i
- **Architecture**: AMD64 (x86)
- **Generation**: 5+
- **Best For**: Spark CPU-heavy jobs, batch processing, x86-optimized ML training

### 2. **compute-optimized-graviton**
- **Purpose**: CPU-intensive ARM64 workloads (cost-optimized)
- **Instance Families**: c6g, c6gd, c6gn, c7g, c7gd, c7gn
- **Architecture**: ARM64 (Graviton)
- **Generation**: 6+ (Graviton 2/3)
- **Best For**: Cost-optimized Spark jobs, ARM64-compatible workloads

### 3. **memory-optimized-x86**
- **Purpose**: Memory-intensive x86 workloads  
- **Instance Families**: r5, r5d, r5n, r6a, r6i, r6id, r6idn, r6in, r7i, x1e, x2iezn
- **Architecture**: AMD64 (x86)
- **Generation**: 5+
- **Best For**: Large Spark datasets, in-memory analytics, x86-specific memory workloads

### 4. **memory-optimized-graviton**
- **Purpose**: Memory-intensive ARM64 workloads (cost-optimized)
- **Instance Families**: r6g, r6gd, r7g, r7gd
- **Architecture**: ARM64 (Graviton)
- **Generation**: 6+ (Graviton 2/3)
- **Best For**: Cost-optimized memory workloads, ARM64 in-memory analytics

### 5. **general-purpose** 
- **Purpose**: Balanced workloads (mixed architecture)
- **Instance Families**: m5, m5d, m5n, m6a, m6i, m6id, m6in, m6g, m6gd, m7g, m7gd, m7i, a1
- **Architecture**: AMD64 + ARM64 (flexible)
- **Generation**: 5+
- **Best For**: General applications, microservices, development, mixed workloads

## 🎯 **How Pods Select NodePools**

### **Method 1: nodeSelector (Recommended)**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-spark-job
spec:
  nodeSelector:
    node.kubernetes.io/workload-type: memory-optimized-x86  # Select x86 memory-optimized NodePool
  containers:
    - name: spark
      image: spark:latest
```

### **Method 2: nodeAffinity (Advanced)**
```yaml
apiVersion: v1  
kind: Pod
metadata:
  name: my-compute-job
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node.kubernetes.io/instance-category
                operator: In
                values: ["compute"]
  containers:
    - name: app
      image: my-app:latest
```

### **Method 3: Spark Job Examples**
```yaml
# Spark Job for x86 Memory-Intensive Workload
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication  
metadata:
  name: memory-intensive-x86-job
spec:
  driver:
    nodeSelector:
      node.kubernetes.io/workload-type: memory-optimized-x86
  executor:
    nodeSelector: 
      node.kubernetes.io/workload-type: memory-optimized-x86
```

```yaml
# Spark Job for Cost-Optimized Graviton Workload  
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: compute-optimized-graviton-job
spec:
  driver:
    nodeSelector:
      node.kubernetes.io/workload-type: compute-optimized-graviton
  executor:
    nodeSelector:
      node.kubernetes.io/workload-type: compute-optimized-graviton  
```

```yaml
# Spark Job for Mixed Architecture (General Purpose)
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: general-purpose-job
spec:
  driver:
    nodeSelector:
      node.kubernetes.io/workload-type: general-purpose  # Can get x86 or ARM64
  executor:
    nodeSelector:
      node.kubernetes.io/workload-type: general-purpose
```

## 🏷️ **Available Node Labels**

Each NodePool automatically applies these labels to nodes:

| Label | Values | Description |
|-------|--------|-------------|
| `karpenter.sh/nodepool` | `compute-optimized-x86`, `compute-optimized-graviton`, `memory-optimized-x86`, `memory-optimized-graviton`, `general-purpose` | NodePool identifier |
| `node.kubernetes.io/workload-type` | Same as above | Workload category for nodeSelector |
| `node.kubernetes.io/instance-category` | `compute`, `memory`, `general` | Instance category |
| `node.kubernetes.io/arch` | `amd64`, `arm64` | CPU architecture |

## 💰 **Cost Optimization**

- **NodePools prefer Spot instances** for cost savings
- **Graviton NodePool** provides 20-40% cost reduction  
- **Automatic consolidation** removes underutilized nodes
- **Resource limits** prevent runaway costs

## ⚡ **Performance Optimization**

- **Instance store RAID0** for high I/O workloads
- **Modern instance generations** (Gen 4+)  
- **Nitro system** for better performance
- **Flexible instance sizes** for optimal resource utilization

## 🔧 **Deployment**

These NodePools are deployed via **ArgoCD** when `enable_karpenter_resources = true` is set in the blueprint configuration. No additional Helm values are needed - the NodePools are designed to be generic and flexible.