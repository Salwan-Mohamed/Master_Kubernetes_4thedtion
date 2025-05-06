#!/bin/bash
# Kubernetes Architecture Demo
# This script demonstrates key Kubernetes concepts from Chapter 1

set -e

echo "=== Kubernetes Architecture Demo ==="
echo "This script demonstrates fundamental Kubernetes concepts."
echo

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl not found. Please install kubectl first."
    exit 1
fi

# Check if we have a Kubernetes cluster accessible
echo "Checking Kubernetes cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to a Kubernetes cluster."
    echo "Please set up a cluster using minikube, kind, or a cloud provider."
    exit 1
fi

echo "✅ Connected to Kubernetes cluster"
kubectl cluster-info | head -n 2
echo

# Create a namespace for our demo
NAMESPACE="k8s-arch-demo"
echo "Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE 2>/dev/null || echo "Namespace already exists"
echo

# 1. Core Concepts: Deployment, ReplicaSet, Pod
echo "=== CORE CONCEPTS DEMO ==="
echo "Demonstrating Deployment -> ReplicaSet -> Pod relationship"
echo

cat <<EOF > demo-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  namespace: $NAMESPACE
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.23.1
        ports:
        - containerPort: 80
EOF

echo "Creating deployment..."
kubectl apply -f demo-deployment.yaml

echo "Waiting for deployment to be ready..."
kubectl -n $NAMESPACE rollout status deployment/nginx-deployment

echo "✅ Deployment created successfully"
echo

echo "Resource hierarchy:"
echo "1. Deployment:"
kubectl -n $NAMESPACE get deployments -o wide

echo "2. ReplicaSet (created automatically by Deployment):"
kubectl -n $NAMESPACE get replicasets -o wide

echo "3. Pods (created automatically by ReplicaSet):"
kubectl -n $NAMESPACE get pods -o wide
echo

# 2. Self-healing demonstration
echo "=== SELF-HEALING DEMO ==="
echo "Kubernetes maintains desired state via reconciliation loops"
echo

POD_NAME=$(kubectl -n $NAMESPACE get pods -l app=nginx -o jsonpath='{.items[0].metadata.name}')
echo "Deleting a pod to demonstrate self-healing: $POD_NAME"
kubectl -n $NAMESPACE delete pod $POD_NAME

echo "Watching as Kubernetes creates a replacement pod..."
sleep 5
kubectl -n $NAMESPACE get pods -l app=nginx

echo "✅ Kubernetes automatically created a new pod to maintain desired state"
echo

# 3. Sidecar Pattern
echo "=== SIDECAR PATTERN DEMO ==="
echo "The sidecar pattern adds functionality to a main application"
echo

cat <<EOF > sidecar-demo.yaml
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-demo
  namespace: $NAMESPACE
spec:
  containers:
  - name: main-app
    image: nginx:1.23.1
    ports:
    - containerPort: 80
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
  - name: log-sidecar
    image: busybox:1.36
    command: ["/bin/sh", "-c", "tail -f /var/log/nginx/access.log"]
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
  volumes:
  - name: shared-logs
    emptyDir: {}
EOF

echo "Creating a pod with sidecar container..."
kubectl apply -f sidecar-demo.yaml

echo "Waiting for sidecar pod to be ready..."
kubectl -n $NAMESPACE wait --for=condition=Ready pod/sidecar-demo --timeout=60s

echo "✅ Sidecar pod created successfully"
echo "Sidecar container has access to the main container's logs"
echo

# 4. Level-triggered architecture simulation
echo "=== LEVEL-TRIGGERED ARCHITECTURE DEMO ==="
echo "Demonstrating how Kubernetes continuously reconciles actual state with desired state"
echo

echo "Changing deployment's desired state to 5 replicas..."
kubectl -n $NAMESPACE scale deployment nginx-deployment --replicas=5

echo "Watching as Kubernetes scales up to match the new desired state..."
sleep 5
kubectl -n $NAMESPACE get pods -l app=nginx

echo "✅ Kubernetes automatically scaled up to 5 pods"
echo

echo "Now reducing desired state to 2 replicas..."
kubectl -n $NAMESPACE scale deployment nginx-deployment --replicas=2

echo "Watching as Kubernetes scales down to match the new desired state..."
sleep 5
kubectl -n $NAMESPACE get pods -l app=nginx

echo "✅ Kubernetes automatically scaled down to 2 pods"
echo

# 5. Service Discovery & Networking
echo "=== SERVICE DISCOVERY DEMO ==="
echo "Creating a service to demonstrate the Service abstraction"
echo

cat <<EOF > demo-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: $NAMESPACE
spec:
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

echo "Creating service..."
kubectl apply -f demo-service.yaml

echo "Service details:"
kubectl -n $NAMESPACE get service nginx-service -o wide
echo

echo "Service endpoints (automatically managed by Kubernetes):"
kubectl -n $NAMESPACE get endpoints nginx-service
echo

echo "✅ Service created and endpoints automatically configured"
echo

# 6. API Groups exploration
echo "=== API GROUPS EXPLORATION ==="
echo "Exploring the API groups that organize Kubernetes resources"
echo

echo "API versions available:"
kubectl api-versions | head -n 10
echo "..."
echo

echo "Resources in the 'apps' API group:"
kubectl api-resources --api-group=apps -o wide
echo

echo "Resources in the 'core' API group:"
kubectl api-resources --api-group= -o wide | head -n 10
echo "..."
echo

# 7. Ambassador Pattern Demo
echo "=== AMBASSADOR PATTERN DEMO ==="
echo "The ambassador pattern simplifies access to external services"
echo

cat <<EOF > ambassador-demo.yaml
apiVersion: v1
kind: Pod
metadata:
  name: ambassador-demo
  namespace: $NAMESPACE
spec:
  containers:
  - name: main-app
    image: busybox:1.36
    command: ["/bin/sh", "-c", "while true; do wget -q -O- http://localhost:8080/api; sleep 5; done"]
  - name: ambassador
    image: hashicorp/http-echo:0.2.3
    args:
    - "-text={\"result\":\"Success\",\"source\":\"Local Ambassador\"}"
    - "-listen=:8080"
    ports:
    - containerPort: 8080
EOF

echo "Creating pod with ambassador container..."
kubectl apply -f ambassador-demo.yaml

echo "Waiting for ambassador pod to be ready..."
kubectl -n $NAMESPACE wait --for=condition=Ready pod/ambassador-demo --timeout=60s || echo "Pod may still be initializing, continuing..."
sleep 5

echo "✅ Ambassador pod created"
echo "Main app is making requests through the ambassador:"
kubectl -n $NAMESPACE logs ambassador-demo -c main-app | tail -n 3
echo

# 8. Adapter Pattern Demo
echo "=== ADAPTER PATTERN DEMO ==="
echo "The adapter pattern transforms output formats"
echo

cat <<EOF > adapter-demo.yaml
apiVersion: v1
kind: Pod
metadata:
  name: adapter-demo
  namespace: $NAMESPACE
spec:
  containers:
  - name: main-app
    image: busybox:1.36
    command: ["/bin/sh", "-c", "while true; do date +\"%s - App log: User login event id=\$RANDOM status=success\" >> /var/log/app.log; sleep 5; done"]
    volumeMounts:
    - name: app-logs
      mountPath: /var/log
  - name: log-adapter
    image: busybox:1.36
    command: ["/bin/sh", "-c", "tail -f /var/log/app.log | while read line; do timestamp=\$(echo \$line | cut -d' ' -f1); msg=\$(echo \$line | cut -d':' -f2-); echo \"{\\\"time\\\":\$timestamp,\\\"message\\\":\\\"\$msg\\\",\\\"level\\\":\\\"info\\\",\\\"format\\\":\\\"json\\\"}\" >> /var/log/transformed.log; done"]
    volumeMounts:
    - name: app-logs
      mountPath: /var/log
  volumes:
  - name: app-logs
    emptyDir: {}
EOF

echo "Creating pod with adapter container..."
kubectl apply -f adapter-demo.yaml

echo "Waiting for adapter pod to be ready..."
kubectl -n $NAMESPACE wait --for=condition=Ready pod/adapter-demo --timeout=60s || echo "Pod may still be initializing, continuing..."
sleep 10

echo "✅ Adapter pod created"
echo "Original log format from main container:"
kubectl -n $NAMESPACE logs adapter-demo -c main-app | tail -n 2
echo
echo "Transformed log format from adapter container:"
kubectl -n $NAMESPACE exec adapter-demo -c log-adapter -- cat /var/log/transformed.log | tail -n 2
echo

# 9. Container Runtime Investigation
echo "=== CONTAINER RUNTIME EXPLORATION ==="
echo "Examining the container runtime used by the cluster"
echo

echo "Container Runtime Version from node info:"
kubectl get nodes -o wide | grep -i "container-runtime"
echo

# 10. Namespaces and Resource Isolation
echo "=== NAMESPACE ISOLATION DEMO ==="
echo "Namespaces provide a way to divide cluster resources"
echo

echo "Current namespaces in the cluster:"
kubectl get namespaces
echo

echo "Resources in our demo namespace ($NAMESPACE):"
kubectl -n $NAMESPACE get all
echo

# Clean up
echo "=== CLEANUP ==="
echo "Removing demo resources..."

read -p "Do you want to clean up all demo resources? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl delete namespace $NAMESPACE
    rm -f demo-deployment.yaml sidecar-demo.yaml demo-service.yaml ambassador-demo.yaml adapter-demo.yaml
    echo "✅ All demo resources removed"
else
    echo "Skipping cleanup. Resources remain in namespace: $NAMESPACE"
fi

echo
echo "Demo complete! You've seen key Kubernetes architecture concepts in action:"
echo "- Core resources: Deployments, ReplicaSets, and Pods"
echo "- Self-healing capabilities through reconciliation"
echo "- Single-node patterns: Sidecar, Ambassador, and Adapter"
echo "- Level-triggered architecture for maintaining desired state"
echo "- Service discovery and networking abstractions"
echo "- API groups organization"
echo "- Container runtimes and namespace isolation"
echo
echo "For more in-depth exploration, check out the exercises in the chapter."
