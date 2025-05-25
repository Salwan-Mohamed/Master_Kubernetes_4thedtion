# Autoscaling Strategies

## Overview

Autoscaling is crucial for maintaining performance while optimizing costs in Kubernetes clusters. This section covers the three main types of autoscaling and how to implement them effectively for high availability systems.

## Kubernetes Autoscaling Landscape

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Autoscaling                    │
├─────────────────┬─────────────────┬─────────────────────────┤
│       HPA       │       VPA       │          CAS            │
│ (Horizontal Pod │ (Vertical Pod   │  (Cluster Autoscaler)   │
│  Autoscaler)    │  Autoscaler)    │                         │
├─────────────────┼─────────────────┼─────────────────────────┤
│ Scales replicas │ Scales resources│ Scales nodes            │
│ CPU/Memory/     │ CPU/Memory      │ Based on pending pods   │
│ Custom metrics  │ requests/limits │ Resource availability   │
└─────────────────┴─────────────────┴─────────────────────────┘
```

## 1. Horizontal Pod Autoscaler (HPA)

**Automatically scales the number of pod replicas based on observed metrics**

### Basic CPU-based HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: webapp-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webapp
  minReplicas: 3
  maxReplicas: 100
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70  # Target 70% CPU utilization
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80  # Target 80% memory utilization
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60  # Wait 60s before scaling up
      policies:
      - type: Percent
        value: 50  # Scale up by max 50% of current replicas
        periodSeconds: 60
      - type: Pods
        value: 4   # Scale up by max 4 pods at a time
        periodSeconds: 60
      selectPolicy: Min  # Use the more conservative policy
    scaleDown:
      stabilizationWindowSeconds: 300  # Wait 5 minutes before scaling down
      policies:
      - type: Percent
        value: 10  # Scale down by max 10% of current replicas
        periodSeconds: 60
```

### Advanced HPA with Custom Metrics

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: advanced-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-service
  minReplicas: 5
  maxReplicas: 50
  metrics:
  # CPU and Memory
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
  
  # Custom metric: requests per second
  - type: Pods
    pods:
      metric:
        name: requests_per_second
      target:
        type: AverageValue
        averageValue: "100"  # 100 RPS per pod
  
  # External metric: SQS queue length
  - type: External
    external:
      metric:
        name: sqs_queue_length
        selector:
          matchLabels:
            queue: "processing-queue"
      target:
        type: Value
        value: "10"  # Max 10 messages per replica
  
  # Object metric: Ingress requests
  - type: Object
    object:
      metric:
        name: requests_per_second
      describedObject:
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        name: api-ingress
      target:
        type: Value
        value: "500"  # 500 RPS total
```

### HPA Status Monitoring

```bash
#!/bin/bash
# hpa-monitor.sh - Monitor HPA status and decisions

echo "=== HPA Status Report ==="
echo "Date: $(date)"
echo

# Get all HPAs with their current status
echo "Current HPA Status:"
kubectl get hpa --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,TARGETS:.status.currentMetrics[*].resource.current.averageUtilization,MINPODS:.spec.minReplicas,MAXPODS:.spec.maxReplicas,REPLICAS:.status.currentReplicas

echo
echo "Detailed HPA Metrics:"
for hpa in $(kubectl get hpa --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}'); do
    namespace=$(echo $hpa | cut -d' ' -f1)
    name=$(echo $hpa | cut -d' ' -f2)
    
    echo "--- $namespace/$name ---"
    kubectl describe hpa $name -n $namespace | grep -E "(Current|Target|Min|Max)"
    echo
done

# Check for scaling events
echo "Recent HPA Events:"
kubectl get events --all-namespaces --field-selector involvedObject.kind=HorizontalPodAutoscaler --sort-by='.lastTimestamp' | tail -20
```

## 2. Vertical Pod Autoscaler (VPA)

**Automatically adjusts CPU and memory requests/limits for pods**

### VPA Installation

```bash
#!/bin/bash
# install-vpa.sh

# Clone VPA repository
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler/

# Install VPA components
./hack/vpa-install.sh

# Verify installation
kubectl get pods -n kube-system | grep vpa
```

### VPA Configuration Examples

#### Recommendation Mode (Safe)
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: webapp-vpa-recommender
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webapp
  updatePolicy:
    updateMode: "Off"  # Only provide recommendations
  resourcePolicy:
    containerPolicies:
    - containerName: webapp
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 2
        memory: 4Gi
      controlledResources: ["cpu", "memory"]
      controlledValues: RequestsAndLimits
```

#### Auto Mode (Active Resizing)
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: webapp-vpa-auto
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webapp
  updatePolicy:
    updateMode: "Auto"  # Automatically apply recommendations
    minReplicas: 2      # Ensure minimum availability during updates
  resourcePolicy:
    containerPolicies:
    - containerName: webapp
      minAllowed:
        cpu: 200m
        memory: 256Mi
      maxAllowed:
        cpu: 1
        memory: 2Gi
      controlledResources: ["cpu", "memory"]
```

#### Initial Mode (Set Once)
```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: webapp-vpa-initial
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webapp
  updatePolicy:
    updateMode: "Initial"  # Only set resources for new pods
  resourcePolicy:
    containerPolicies:
    - containerName: webapp
      minAllowed:
        cpu: 100m
        memory: 128Mi
      maxAllowed:
        cpu: 4
        memory: 8Gi
```

### VPA Monitoring Script

```bash
#!/bin/bash
# vpa-recommendations.sh - Get VPA recommendations

echo "=== VPA Recommendations Report ==="
echo "Generated: $(date)"
echo

for vpa in $(kubectl get vpa --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}'); do
    namespace=$(echo $vpa | cut -d' ' -f1)
    name=$(echo $vpa | cut -d' ' -f2)
    
    echo "--- VPA: $namespace/$name ---"
    
    # Get current recommendations
    kubectl get vpa $name -n $namespace -o jsonpath='{
        "Target CPU: "}{.status.recommendation.containerRecommendations[0].target.cpu}{"\n"}
        {"Target Memory: "}{.status.recommendation.containerRecommendations[0].target.memory}{"\n"}
        {"Lower Bound CPU: "}{.status.recommendation.containerRecommendations[0].lowerBound.cpu}{"\n"}
        {"Lower Bound Memory: "}{.status.recommendation.containerRecommendations[0].lowerBound.memory}{"\n"}
        {"Upper Bound CPU: "}{.status.recommendation.containerRecommendations[0].upperBound.cpu}{"\n"}
        {"Upper Bound Memory: "}{.status.recommendation.containerRecommendations[0].upperBound.memory}{"\n"}
    '
    
    echo
done
```

## 3. Cluster Autoscaler (CAS)

**Automatically scales the number of nodes in the cluster**

### Cluster Autoscaler Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cluster-autoscaler
  namespace: kube-system
  labels:
    app: cluster-autoscaler
spec:
  selector:
    matchLabels:
      app: cluster-autoscaler
  template:
    metadata:
      labels:
        app: cluster-autoscaler
    spec:
      priorityClassName: system-cluster-critical
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        fsGroup: 65534
      serviceAccountName: cluster-autoscaler
      containers:
      - image: k8s.gcr.io/autoscaling/cluster-autoscaler:v1.21.0
        name: cluster-autoscaler
        resources:
          limits:
            cpu: 100m
            memory: 600Mi
          requests:
            cpu: 100m
            memory: 600Mi
        command:
        - ./cluster-autoscaler
        - --v=4
        - --stderrthreshold=info
        - --cloud-provider=aws
        - --skip-nodes-with-local-storage=false
        - --expander=least-waste
        - --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/my-cluster
        - --balance-similar-node-groups
        - --scale-down-enabled=true
        - --scale-down-delay-after-add=10m
        - --scale-down-unneeded-time=10m
        - --scale-down-utilization-threshold=0.5
        - --max-node-provision-time=15m
        env:
        - name: AWS_REGION
          value: us-west-2
        volumeMounts:
        - name: ssl-certs
          mountPath: /etc/ssl/certs/ca-certificates.crt
          readOnly: true
        imagePullPolicy: Always
      volumes:
      - name: ssl-certs
        hostPath:
          path: /etc/ssl/certs/ca-bundle.crt
```

### Multi-Node Group Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-autoscaler-config
  namespace: kube-system
data:
  nodes.max: "100"
  nodes.min: "3"
  scale-down-delay-after-add: "10m"
  scale-down-unneeded-time: "10m"
  
  # Node group configurations
  node-groups: |
    - name: general-purpose
      minSize: 3
      maxSize: 20
      instanceTypes: ["m5.large", "m5.xlarge"]
      zones: ["us-west-2a", "us-west-2b", "us-west-2c"]
      
    - name: compute-optimized
      minSize: 0
      maxSize: 10
      instanceTypes: ["c5.large", "c5.xlarge", "c5.2xlarge"]
      zones: ["us-west-2a", "us-west-2b"]
      taints:
        - key: "compute-intensive"
          value: "true"
          effect: "NoSchedule"
    
    - name: memory-optimized
      minSize: 0
      maxSize: 5
      instanceTypes: ["r5.large", "r5.xlarge"]
      zones: ["us-west-2a", "us-west-2c"]
      taints:
        - key: "memory-intensive"
          value: "true"
          effect: "NoSchedule"
```

### CAS Monitoring and Alerting

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: cas-monitoring
data:
  prometheus-rules.yml: |
    groups:
    - name: cluster-autoscaler
      rules:
      - alert: ClusterAutoscalerUnschedulablePods
        expr: cluster_autoscaler_unschedulable_pods_count > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Cluster Autoscaler has unschedulable pods"
          description: "{{ $value }} pods cannot be scheduled"
      
      - alert: ClusterAutoscalerNodeGroupAtMax
        expr: cluster_autoscaler_node_group_size == cluster_autoscaler_node_group_max_size
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Node group has reached maximum size"
          description: "Node group {{ $labels.node_group }} is at maximum capacity"
      
      - alert: ClusterAutoscalerScaleUpFailure
        expr: increase(cluster_autoscaler_failed_scale_ups_total[10m]) > 3
        labels:
          severity: critical
        annotations:
          summary: "Cluster Autoscaler scale-up failures"
          description: "Multiple scale-up failures detected"
  
  monitoring-script.sh: |
    #!/bin/bash
    # Monitor Cluster Autoscaler status
    
    echo "=== Cluster Autoscaler Status ==="
    echo "Date: $(date)"
    echo
    
    # Check CAS pod status
    echo "Cluster Autoscaler Pod Status:"
    kubectl get pods -n kube-system -l app=cluster-autoscaler
    echo
    
    # Check node group status
    echo "Node Groups Status:"
    kubectl logs -n kube-system -l app=cluster-autoscaler --tail=50 | grep -E "(node group|scale)"
    echo
    
    # Check for pending pods
    echo "Pending Pods (may trigger scaling):"
    kubectl get pods --all-namespaces --field-selector=status.phase=Pending
    echo
    
    # Resource utilization
    echo "Node Resource Utilization:"
    kubectl top nodes
```

## 4. Custom Metrics Autoscaling

### KEDA (Kubernetes Event Driven Autoscaling)

```bash
# Install KEDA
kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.8.0/keda-2.8.0.yaml
```

### Queue-based Scaling Example

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: queue-processor-scaler
spec:
  scaleTargetRef:
    name: queue-processor
  minReplicaCount: 1
  maxReplicaCount: 50
  triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: https://sqs.us-west-2.amazonaws.com/123456789/processing-queue
      queueLength: '10'  # Scale up when queue has > 10 messages
      awsRegion: us-west-2
    authenticationRef:
      name: aws-credentials
---
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-credentials
spec:
  secretTargetRef:
  - parameter: awsAccessKeyID
    name: aws-secret
    key: access-key
  - parameter: awsSecretAccessKey
    name: aws-secret
    key: secret-key
```

### Prometheus Metrics Scaling

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: http-requests-scaler
spec:
  scaleTargetRef:
    name: web-app
  minReplicaCount: 2
  maxReplicaCount: 20
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus:9090
      metricName: http_requests_per_second
      threshold: '100'
      query: sum(rate(http_requests_total{service="web-app"}[1m]))
```

## Integration Patterns

### HPA + VPA Integration

```yaml
# Use HPA for replica scaling, VPA for resource sizing
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: webapp-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webapp
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
---
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: webapp-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: webapp
  updatePolicy:
    updateMode: "Auto"
  resourcePolicy:
    containerPolicies:
    - containerName: webapp
      controlledResources: ["memory"]  # Only control memory, let HPA handle CPU
      maxAllowed:
        memory: 4Gi
```

### Complete Autoscaling Stack

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: autoscaling-stack
data:
  deployment.yaml: |
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: scalable-app
    spec:
      replicas: 3
      selector:
        matchLabels:
          app: scalable-app
      template:
        metadata:
          labels:
            app: scalable-app
        spec:
          containers:
          - name: app
            image: myapp:1.0
            resources:
              requests:
                cpu: 200m
                memory: 256Mi
              limits:
                cpu: 500m
                memory: 512Mi
            livenessProbe:
              httpGet:
                path: /health
                port: 8080
            readinessProbe:
              httpGet:
                path: /ready
                port: 8080
  
  hpa.yaml: |
    apiVersion: autoscaling/v2
    kind: HorizontalPodAutoscaler
    metadata:
      name: scalable-app-hpa
    spec:
      scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: scalable-app
      minReplicas: 3
      maxReplicas: 50
      metrics:
      - type: Resource
        resource:
          name: cpu
          target:
            type: Utilization
            averageUtilization: 70
      - type: Resource
        resource:
          name: memory
          target:
            type: Utilization
            averageUtilization: 80
  
  pdb.yaml: |
    apiVersion: policy/v1
    kind: PodDisruptionBudget
    metadata:
      name: scalable-app-pdb
    spec:
      minAvailable: 2
      selector:
        matchLabels:
          app: scalable-app
```

## Autoscaling Best Practices

### 1. Resource Requests and Limits
```yaml
# Always set appropriate resource requests for HPA to work
resources:
  requests:
    cpu: 200m      # HPA bases calculations on requests
    memory: 256Mi
  limits:
    cpu: 500m      # Prevent resource starvation
    memory: 512Mi
```

### 2. Gradual Scaling Policies
```yaml
behavior:
  scaleUp:
    stabilizationWindowSeconds: 60
    policies:
    - type: Percent
      value: 25  # Scale up by max 25% at a time
      periodSeconds: 60
  scaleDown:
    stabilizationWindowSeconds: 300  # Wait 5 minutes before scaling down
    policies:
    - type: Percent
      value: 10  # Scale down conservatively
      periodSeconds: 60
```

### 3. Monitoring and Alerting
```bash
#!/bin/bash
# autoscaling-health-check.sh

echo "=== Autoscaling Health Check ==="

# Check HPA status
echo "HPA Status:"
kubectl get hpa --all-namespaces | grep -v "<unknown>"

# Check VPA recommendations
echo "\nVPA Recommendations Available:"
kubectl get vpa --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,TARGET-CPU:.status.recommendation.containerRecommendations[0].target.cpu,TARGET-MEMORY:.status.recommendation.containerRecommendations[0].target.memory

# Check Cluster Autoscaler logs for errors
echo "\nCluster Autoscaler Recent Activity:"
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=20 | grep -E "(ERROR|scale|node)"

# Check for pending pods that might need scaling
echo "\nPending Pods:"
kubectl get pods --all-namespaces --field-selector=status.phase=Pending --no-headers | wc -l
```

## Troubleshooting Common Issues

### HPA Not Scaling
```bash
# Debug HPA issues
kubectl describe hpa <hpa-name>
kubectl top pods  # Check if metrics are available
kubectl get --raw /apis/metrics.k8s.io/v1beta1/pods  # Check metrics API
```

### VPA Not Applying Recommendations
```bash
# Check VPA admission controller
kubectl get pods -n kube-system | grep vpa
kubectl logs -n kube-system -l app=vpa-admission-controller
```

### Cluster Autoscaler Not Adding Nodes
```bash
# Check CAS configuration and logs
kubectl describe configmap cluster-autoscaler-config -n kube-system
kubectl logs -n kube-system -l app=cluster-autoscaler --tail=100
```

## Next Steps

- [Performance Optimization](../performance/)
- [Testing and Validation](../testing/)
- [Practical Exercises](../exercises/)
- [Code Examples](../code-examples/)

---

*Effective autoscaling requires careful configuration, monitoring, and regular tuning based on your application's behavior and requirements.*