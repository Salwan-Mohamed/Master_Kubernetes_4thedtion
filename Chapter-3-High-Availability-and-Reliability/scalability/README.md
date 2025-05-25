# Scalability and Capacity Planning

## Overview

Highly available systems must also be scalable. System load varies dramatically based on time, user behavior, and business cycles. This section covers strategies for managing cluster capacity and ensuring your systems can handle both expected and unexpected load patterns.

## Availability Requirements Spectrum

Different systems have vastly different reliability and availability requirements. Understanding where your system fits on this spectrum is crucial for making the right trade-offs.

### 1. Best Effort

**"If it works, great! If it doesn't – oh well."**

**Characteristics**:
- No guarantees whatsoever
- Suitable for development environments
- Internal tools with high change frequency
- Beta services

**Pros**:
✅ Developers can move fast and break things
✅ No rigorous testing requirements
✅ Lower operational overhead
✅ Potentially better performance (fewer verification steps)

**Cons**:
❌ No reliability guarantees
❌ Can impact productivity if overused
❌ Not suitable for business-critical systems

**Implementation**:
```yaml
# Basic deployment - no HA considerations
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dev-app
spec:
  replicas: 1  # Single replica
  selector:
    matchLabels:
      app: dev-app
  template:
    metadata:
      labels:
        app: dev-app
    spec:
      containers:
      - name: app
        image: myapp:latest
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
        # No health checks for simplicity
```

### 2. Maintenance Windows

**Planned downtime for system maintenance**

**Use Cases**:
- Systems with limited usage windows (office hours only)
- Legacy applications requiring offline updates
- Cost-sensitive environments

**Benefits**:
✅ Simplified operations (no live maintenance)
✅ Lower complexity and cost
✅ Easier to troubleshoot issues

**Drawbacks**:
❌ System unavailable during maintenance
❌ Limited to specific usage patterns
❌ Poor user experience during windows

**Implementation Strategy**:
```bash
#!/bin/bash
# maintenance-window.sh - Maintenance window automation

echo "Starting maintenance window at $(date)"

# 1. Redirect traffic to maintenance page
kubectl patch ingress webapp-ingress -p '{
  "spec": {
    "rules": [{
      "host": "example.com",
      "http": {
        "paths": [{
          "path": "/",
          "pathType": "Prefix",
          "backend": {
            "service": {
              "name": "maintenance-page",
              "port": {"number": 80}
            }
          }
        }]
      }
    }]
  }
}'

# 2. Perform maintenance tasks
kubectl apply -f new-deployment.yaml
kubectl rollout status deployment/webapp

# 3. Restore normal traffic
kubectl patch ingress webapp-ingress -p '{
  "spec": {
    "rules": [{
      "host": "example.com",
      "http": {
        "paths": [{
          "path": "/",
          "pathType": "Prefix",
          "backend": {
            "service": {
              "name": "webapp-service",
              "port": {"number": 80}
            }
          }
        }]
      }
    }]
  }
}'

echo "Maintenance window completed at $(date)"
```

### 3. Quick Recovery

**Focus on minimizing Mean Time To Recovery (MTTR)**

**Key Metrics**:
- **MTTR**: Mean Time To Recovery
- **RTO**: Recovery Time Objective
- **RPO**: Recovery Point Objective

**Strategies**:

#### Blue-Green Deployment
```yaml
# Blue environment (current production)
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: webapp-rollout
spec:
  replicas: 5
  strategy:
    blueGreen:
      activeService: webapp-active
      previewService: webapp-preview
      autoPromotionEnabled: false
      scaleDownDelaySeconds: 30
      prePromotionAnalysis:
        templates:
        - templateName: success-rate
        args:
        - name: service-name
          value: webapp-preview
      postPromotionAnalysis:
        templates:
        - templateName: success-rate
        args:
        - name: service-name
          value: webapp-active
  selector:
    matchLabels:
      app: webapp
  template:
    metadata:
      labels:
        app: webapp
    spec:
      containers:
      - name: webapp
        image: myapp:v2.0
```

#### Automated Rollback Configuration
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: rollback-config
data:
  rollback-trigger.sh: |
    #!/bin/bash
    # Monitor error rates and trigger rollback
    ERROR_RATE=$(curl -s "http://prometheus:9090/api/v1/query?query=rate(http_requests_total{status=~'5..'}[5m])" | jq -r '.data.result[0].value[1]')
    
    if (( $(echo "$ERROR_RATE > 0.05" | bc -l) )); then
        echo "High error rate detected: $ERROR_RATE. Triggering rollback..."
        kubectl rollout undo deployment/webapp
        kubectl rollout status deployment/webapp
    fi
```

### 4. Zero Downtime (The Holy Grail)

**Design principles for continuous availability**

> **Reality Check**: True zero downtime is impossible. All systems fail. The goal is to minimize downtime through design and preparation.

#### Core Requirements

**1. Redundancy at Every Level**
```yaml
# Multi-AZ deployment with anti-affinity
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zero-downtime-app
spec:
  replicas: 6  # Minimum 2 per AZ
  selector:
    matchLabels:
      app: zero-downtime-app
  template:
    metadata:
      labels:
        app: zero-downtime-app
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: zero-downtime-app
            topologyKey: kubernetes.io/hostname
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app: zero-downtime-app
              topologyKey: topology.kubernetes.io/zone
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
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: zero-downtime-pdb
spec:
  minAvailable: 4  # Always keep 4 pods running
  selector:
    matchLabels:
      app: zero-downtime-app
```

**2. Automated Hot-Swapping**
```yaml
# Service with session affinity disabled for better failover
apiVersion: v1
kind: Service
metadata:
  name: zero-downtime-service
spec:
  selector:
    app: zero-downtime-app
  ports:
  - port: 80
    targetPort: 8080
  sessionAffinity: None  # Allow requests to any healthy pod
  type: ClusterIP
---
# Ingress with proper health checks
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: zero-downtime-ingress
  annotations:
    nginx.ingress.kubernetes.io/upstream-hash-by: "$request_uri"
    nginx.ingress.kubernetes.io/load-balance: "round_robin"
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: zero-downtime-service
            port:
              number: 80
```

**3. Comprehensive Monitoring and Alerting**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-rules
data:
  rules.yml: |
    groups:
    - name: zero-downtime-app
      rules:
      - alert: HighErrorRate
        expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "High error rate detected"
          description: "Error rate is {{ $value }} for the last 5 minutes"
      
      - alert: PodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Pod is crash looping"
          description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} is restarting frequently"
      
      - alert: LowPodAvailability
        expr: kube_deployment_status_replicas_available{deployment="zero-downtime-app"} < 4
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Low pod availability"
          description: "Only {{ $value }} pods available for zero-downtime-app"
```

**4. Comprehensive Testing**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: testing-suite
data:
  test-suite.sh: |
    #!/bin/bash
    # Comprehensive testing for zero-downtime deployment
    
    echo "=== Zero Downtime Testing Suite ==="
    
    # Unit tests
    echo "Running unit tests..."
    kubectl run unit-tests --image=test-runner:latest --rm -i --restart=Never -- npm test
    
    # Integration tests
    echo "Running integration tests..."
    kubectl apply -f integration-test-env.yaml
    kubectl wait --for=condition=ready pod -l app=integration-test --timeout=300s
    kubectl exec -it deployment/integration-test -- python -m pytest tests/integration/
    
    # Load tests
    echo "Running load tests..."
    kubectl run load-test --image=loadtest:latest --rm -i --restart=Never -- \
      artillery run --target https://api.example.com load-test.yml
    
    # Chaos engineering
    echo "Running chaos tests..."
    kubectl apply -f chaos-experiment.yaml
    kubectl wait --for=condition=complete job/chaos-test --timeout=600s
    
    # Security tests
    echo "Running security tests..."
    kubectl run security-scan --image=security-scanner:latest --rm -i --restart=Never -- \
      nmap -sS -O api.example.com
    
    echo "All tests completed successfully!"
```

## Site Reliability Engineering (SRE) Approach

**Real-world approach balancing reliability with feature velocity**

### Service Level Objectives (SLOs)

**Define measurable reliability targets**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: slo-definitions
data:
  slos.yaml: |
    services:
      api-service:
        slos:
          availability:
            target: 99.9%  # 43 minutes downtime per month
            measurement_window: 30d
          latency:
            target: 95th percentile < 200ms
            measurement_window: 7d
          error_rate:
            target: < 0.1%
            measurement_window: 24h
      
      batch-processor:
        slos:
          availability:
            target: 99.5%  # 3.6 hours downtime per month
            measurement_window: 30d
          throughput:
            target: > 1000 jobs/hour
            measurement_window: 24h
```

### Error Budget Implementation

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: error-budget-policy
data:
  policy.sh: |
    #!/bin/bash
    # Error budget enforcement
    
    SERVICE="$1"
    CURRENT_AVAILABILITY=$(curl -s "http://prometheus:9090/api/v1/query?query=avg_over_time(up{service='$SERVICE'}[30d])")
    TARGET_AVAILABILITY=0.999
    
    ERROR_BUDGET=$(echo "1 - $TARGET_AVAILABILITY" | bc -l)
    CURRENT_ERROR_RATE=$(echo "1 - $CURRENT_AVAILABILITY" | bc -l)
    
    if (( $(echo "$CURRENT_ERROR_RATE > $ERROR_BUDGET" | bc -l) )); then
        echo "ERROR: $SERVICE has exceeded error budget!"
        echo "Current availability: $CURRENT_AVAILABILITY"
        echo "Error budget exhausted - no new deployments until reliability improves"
        exit 1
    else
        REMAINING_BUDGET=$(echo "$ERROR_BUDGET - $CURRENT_ERROR_RATE" | bc -l)
        echo "$SERVICE error budget status: ${REMAINING_BUDGET} remaining"
        exit 0
    fi
```

### Capacity Planning Formula

**Intent-based capacity planning**

```bash
# capacity-planning.sh - Automated capacity planning
#!/bin/bash

# Get current metrics
CURRENT_CPU=$(kubectl top nodes | awk 'NR>1 {sum += $3} END {print sum}')
CURRENT_MEMORY=$(kubectl top nodes | awk 'NR>1 {sum += $5} END {print sum}')
CURRENT_PODS=$(kubectl get pods --all-namespaces --no-headers | wc -l)

# Growth projections (example: 20% monthly growth)
GROWTH_RATE=1.2
PROJECTION_MONTHS=3

PROJECTED_CPU=$(echo "$CURRENT_CPU * ($GROWTH_RATE ^ $PROJECTION_MONTHS)" | bc -l)
PROJECTED_MEMORY=$(echo "$CURRENT_MEMORY * ($GROWTH_RATE ^ $PROJECTION_MONTHS)" | bc -l)
PROJECTED_PODS=$(echo "$CURRENT_PODS * ($GROWTH_RATE ^ $PROJECTION_MONTHS)" | bc -l)

# Calculate required capacity with buffer (25% safety margin)
SAFETY_MARGIN=1.25
REQUIRED_CPU=$(echo "$PROJECTED_CPU * $SAFETY_MARGIN" | bc -l)
REQUIRED_MEMORY=$(echo "$PROJECTED_MEMORY * $SAFETY_MARGIN" | bc -l)
REQUIRED_PODS=$(echo "$PROJECTED_PODS * $SAFETY_MARGIN" | bc -l)

echo "Capacity Planning Report:"
echo "Current CPU: ${CURRENT_CPU}m"
echo "Required CPU: ${REQUIRED_CPU}m"
echo "Current Memory: ${CURRENT_MEMORY}Mi"
echo "Required Memory: ${REQUIRED_MEMORY}Mi"
echo "Current Pods: $CURRENT_PODS"
echo "Required Pod Capacity: $REQUIRED_PODS"

# Determine if scaling is needed
if (( $(echo "$REQUIRED_CPU > $CURRENT_CPU * 0.8" | bc -l) )); then
    echo "⚠️  CPU scaling recommended"
fi

if (( $(echo "$REQUIRED_MEMORY > $CURRENT_MEMORY * 0.8" | bc -l) )); then
    echo "⚠️  Memory scaling recommended"
fi
```

## Cost vs. Performance Trade-offs

### Resource Optimization Strategies

**1. Right-sizing Resources**
```yaml
# Resource optimization with VPA recommendations
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
    updateMode: "Off"  # Recommendation only
  resourcePolicy:
    containerPolicies:
    - containerName: webapp
      maxAllowed:
        cpu: 1
        memory: 1Gi
      minAllowed:
        cpu: 100m
        memory: 128Mi
      controlledResources: ["cpu", "memory"]
```

**2. Spot Instance Utilization**
```yaml
# Node pool with mixed instance types
apiVersion: v1
kind: ConfigMap
metadata:
  name: spot-instance-config
data:
  cluster-autoscaler-config: |
    nodes:
      - name: spot-pool
        minSize: 0
        maxSize: 10
        instanceTypes:
          - m5.large
          - m5.xlarge
          - m4.large
        spotPrice: "0.10"
        onDemandBaseCapacity: 2
        onDemandPercentage: 20
      - name: on-demand-pool
        minSize: 2
        maxSize: 5
        instanceTypes:
          - m5.large
        spotPrice: null
```

**3. Performance vs. Cost Analysis**
```python
# cost-performance-analyzer.py
import numpy as np
import matplotlib.pyplot as plt

def analyze_cost_performance():
    # Sample data: instance types with performance and cost metrics
    instances = {
        't3.micro': {'cost': 0.0104, 'performance': 0.5, 'vcpu': 2, 'memory': 1},
        't3.small': {'cost': 0.0208, 'performance': 1.0, 'vcpu': 2, 'memory': 2},
        'm5.large': {'cost': 0.096, 'performance': 2.5, 'vcpu': 2, 'memory': 8},
        'm5.xlarge': {'cost': 0.192, 'performance': 5.0, 'vcpu': 4, 'memory': 16},
        'c5.large': {'cost': 0.085, 'performance': 3.0, 'vcpu': 2, 'memory': 4},
    }
    
    # Calculate cost-performance ratio
    for name, specs in instances.items():
        ratio = specs['performance'] / specs['cost']
        print(f"{name}: Performance/Cost = {ratio:.2f}")
    
    # Find optimal configuration for different workload patterns
    workloads = {
        'cpu_intensive': {'cpu_weight': 0.7, 'memory_weight': 0.3},
        'memory_intensive': {'cpu_weight': 0.3, 'memory_weight': 0.7},
        'balanced': {'cpu_weight': 0.5, 'memory_weight': 0.5}
    }
    
    for workload_name, weights in workloads.items():
        print(f"\nOptimal instances for {workload_name} workload:")
        scores = {}
        for name, specs in instances.items():
            score = (specs['vcpu'] * weights['cpu_weight'] + 
                    specs['memory'] * weights['memory_weight']) / specs['cost']
            scores[name] = score
        
        sorted_instances = sorted(scores.items(), key=lambda x: x[1], reverse=True)
        for name, score in sorted_instances[:3]:
            print(f"  {name}: Score = {score:.2f}")

if __name__ == "__main__":
    analyze_cost_performance()
```

## Capacity Planning Best Practices

### 1. Monitor Leading Indicators
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: capacity-metrics
data:
  monitoring-queries.yml: |
    queries:
      # CPU utilization trending
      cpu_utilization_trend:
        query: 'avg_over_time(cluster:cpu_usage_rate[7d])'
        threshold: 0.70
        
      # Memory pressure indicators
      memory_pressure:
        query: 'avg_over_time(cluster:memory_usage_rate[7d])'
        threshold: 0.80
        
      # Pod scheduling failures
      scheduling_failures:
        query: 'rate(scheduler_schedule_attempts_total{result="error"}[5m])'
        threshold: 0.01
        
      # Network bandwidth utilization
      network_utilization:
        query: 'avg_over_time(cluster:network_usage_rate[24h])'
        threshold: 0.75
```

### 2. Implement Predictive Scaling
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: predictive-scaling
data:
  predictor.py: |
    import numpy as np
    from sklearn.linear_model import LinearRegression
    import datetime
    
    def predict_capacity_needs(historical_data, days_ahead=30):
        """
        Predict future capacity needs based on historical trends
        """
        # Convert timestamps to numerical format
        timestamps = np.array([d['timestamp'] for d in historical_data])
        cpu_usage = np.array([d['cpu_usage'] for d in historical_data])
        memory_usage = np.array([d['memory_usage'] for d in historical_data])
        
        # Prepare data for linear regression
        X = timestamps.reshape(-1, 1)
        
        # Train models
        cpu_model = LinearRegression().fit(X, cpu_usage)
        memory_model = LinearRegression().fit(X, memory_usage)
        
        # Predict future usage
        future_timestamp = datetime.datetime.now().timestamp() + (days_ahead * 24 * 3600)
        future_cpu = cpu_model.predict([[future_timestamp]])[0]
        future_memory = memory_model.predict([[future_timestamp]])[0]
        
        return {
            'predicted_cpu_usage': future_cpu,
            'predicted_memory_usage': future_memory,
            'confidence_interval': {
                'cpu': np.std(cpu_usage) * 1.96,  # 95% confidence
                'memory': np.std(memory_usage) * 1.96
            }
        }
```

### 3. Automate Capacity Decisions
```bash
#!/bin/bash
# auto-capacity-management.sh

# Configuration
CPU_THRESHOLD=0.75
MEMORY_THRESHOLD=0.80
SCALE_UP_BUFFER=0.25

# Get current cluster utilization
CURRENT_CPU=$(kubectl top nodes | awk 'NR>1 {sum+=$3; count++} END {print sum/count}')
CURRENT_MEMORY=$(kubectl top nodes | awk 'NR>1 {sum+=$5; count++} END {print sum/count}')

# Check if scaling is needed
if (( $(echo "$CURRENT_CPU > $CPU_THRESHOLD" | bc -l) )); then
    echo "CPU utilization ($CURRENT_CPU) exceeds threshold ($CPU_THRESHOLD)"
    DESIRED_NODES=$(kubectl get nodes --no-headers | wc -l)
    NEW_NODES=$(echo "$DESIRED_NODES * (1 + $SCALE_UP_BUFFER)" | bc -l | cut -d. -f1)
    
    echo "Scaling cluster from $DESIRED_NODES to $NEW_NODES nodes"
    
    # Update cluster autoscaler configuration
    kubectl patch configmap cluster-autoscaler-status -n kube-system --patch='{
        "data": {
            "nodes.max": "'$NEW_NODES'"
        }
    }'
fi

if (( $(echo "$CURRENT_MEMORY > $MEMORY_THRESHOLD" | bc -l) )); then
    echo "Memory utilization ($CURRENT_MEMORY) exceeds threshold ($MEMORY_THRESHOLD)"
    # Similar scaling logic for memory-based scaling
fi
```

## Next Steps

- [Performance Optimization Techniques](../performance/)
- [Autoscaling Implementation](../autoscaling/)
- [Testing and Validation](../testing/)
- [Code Examples and Labs](../exercises/)

---

*Remember: Scalability is not just about handling more load – it's about maintaining performance and availability as your system grows.*