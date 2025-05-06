# Kubernetes Architecture Implementation Guide

This guide provides practical steps to explore and understand Kubernetes architecture concepts covered in Chapter 1.

## Table of Contents
- [Environment Setup](#environment-setup)
- [Exploring Kubernetes Components](#exploring-kubernetes-components)
- [Containerization Basics](#containerization-basics)
- [Kubernetes Design Patterns Implementation](#kubernetes-design-patterns-implementation)
- [Container Runtime Exploration](#container-runtime-exploration)
- [API and Architecture Exploration](#api-and-architecture-exploration)

## Environment Setup

### Option 1: Local Development Environment

#### Installing Minikube

Minikube provides a single-node Kubernetes cluster for local development:

```bash
# macOS (with Homebrew)
brew install minikube

# Linux
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube

# Windows (with Chocolatey)
choco install minikube
```

Start Minikube with:

```bash
minikube start
```

#### Installing Kind (Kubernetes in Docker)

Kind runs Kubernetes clusters using Docker containers as nodes:

```bash
# macOS
brew install kind

# Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.17.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Windows (with Chocolatey)
choco install kind
```

Create a cluster with:

```bash
kind create cluster
```

#### Installing kubectl

Kubectl is the command-line tool for interacting with Kubernetes clusters:

```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Windows (with Chocolatey)
choco install kubernetes-cli
```

### Option 2: Cloud-Based Kubernetes Environments

For larger or more realistic setups, consider:

- **Google Kubernetes Engine (GKE)**: Google Cloud's managed Kubernetes service
- **Amazon Elastic Kubernetes Service (EKS)**: AWS's managed Kubernetes service
- **Azure Kubernetes Service (AKS)**: Microsoft Azure's managed Kubernetes service
- **DigitalOcean Kubernetes**: DigitalOcean's managed Kubernetes service

## Exploring Kubernetes Components

### Examining the Control Plane

Once your cluster is running, explore the control plane components:

```bash
# View the API server and other control plane pods
kubectl get pods -n kube-system

# View component details
kubectl describe pod kube-apiserver-minikube -n kube-system
kubectl describe pod kube-controller-manager-minikube -n kube-system
kubectl describe pod kube-scheduler-minikube -n kube-system
kubectl describe pod etcd-minikube -n kube-system
```

### Exploring Node Components

Examine components on the worker node(s):

```bash
# View node information
kubectl get nodes -o wide

# View node details
kubectl describe node minikube

# If using minikube, SSH into the node to inspect components
minikube ssh

# Once inside, check running containers
docker ps | grep -E 'kubelet|kube-proxy'

# Check kubelet service status
systemctl status kubelet
```

## Containerization Basics

### Building a Simple Container

Create a file named `app.js`:

```javascript
const http = require('http');

const server = http.createServer((req, res) => {
  res.statusCode = 200;
  res.setHeader('Content-Type', 'text/plain');
  res.end('Hello Kubernetes Architecture!\n');
});

const port = process.env.PORT || 3000;
server.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
```

Create a `Dockerfile`:

```dockerfile
FROM node:14-alpine
WORKDIR /app
COPY app.js .
EXPOSE 3000
CMD ["node", "app.js"]
```

Build and run the container:

```bash
docker build -t hello-k8s .
docker run -p 3000:3000 hello-k8s
```

### Deploying to Kubernetes

Create a deployment manifest `hello-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-k8s
spec:
  replicas: 3
  selector:
    matchLabels:
      app: hello-k8s
  template:
    metadata:
      labels:
        app: hello-k8s
    spec:
      containers:
      - name: hello-k8s
        image: hello-k8s
        ports:
        - containerPort: 3000
        resources:
          limits:
            cpu: "0.2"
            memory: "128Mi"
          requests:
            cpu: "0.1"
            memory: "64Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: hello-k8s
spec:
  type: NodePort
  selector:
    app: hello-k8s
  ports:
  - port: 80
    targetPort: 3000
```

If using Minikube, load the image into Minikube's Docker daemon:

```bash
minikube image load hello-k8s
```

Deploy the application:

```bash
kubectl apply -f hello-deployment.yaml

# Check deployment status
kubectl get deployments
kubectl get pods
kubectl get services

# Access the application
minikube service hello-k8s
```

## Kubernetes Design Patterns Implementation

### Implementing the Sidecar Pattern

Create a file named `sidecar-pattern.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sidecar-demo
spec:
  containers:
  - name: main-app
    image: nginx
    ports:
    - containerPort: 80
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
  - name: log-sidecar
    image: busybox
    command: ["/bin/sh", "-c", "tail -f /var/log/nginx/access.log"]
    volumeMounts:
    - name: shared-logs
      mountPath: /var/log/nginx
  volumes:
  - name: shared-logs
    emptyDir: {}
```

Deploy and test:

```bash
kubectl apply -f sidecar-pattern.yaml
kubectl get pods
kubectl port-forward sidecar-demo 8080:80 &
curl http://localhost:8080
kubectl logs sidecar-demo -c log-sidecar
```

### Implementing the Ambassador Pattern

Create a file named `ambassador-pattern.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ambassador-demo
spec:
  containers:
  - name: main-app
    image: busybox
    command: ["/bin/sh", "-c", "while true; do wget -q -O- http://localhost:8080; sleep 5; done"]
  - name: ambassador
    image: hashicorp/http-echo:latest
    args:
    - "-text=Hello from Ambassador"
    - "-listen=:8080"
    ports:
    - containerPort: 8080
```

Deploy and test:

```bash
kubectl apply -f ambassador-pattern.yaml
kubectl get pods
kubectl logs ambassador-demo -c main-app
```

### Implementing the Adapter Pattern

Create a file named `adapter-pattern.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: adapter-demo
spec:
  containers:
  - name: main-app
    image: busybox
    command: ["/bin/sh", "-c", "while true; do echo '{\"timestamp\": \"'$(date +%s)'\", \"level\": \"info\", \"message\": \"Sample log message\"}' >> /var/log/app.log; sleep 5; done"]
    volumeMounts:
    - name: app-logs
      mountPath: /var/log
  - name: log-adapter
    image: busybox
    command: ["/bin/sh", "-c", "tail -f /var/log/app.log | while read line; do echo \"$(date): TRANSFORMED: $line\" | sed 's/{/[/g' | sed 's/}/]/g'; done"]
    volumeMounts:
    - name: app-logs
      mountPath: /var/log
  volumes:
  - name: app-logs
    emptyDir: {}
```

Deploy and test:

```bash
kubectl apply -f adapter-pattern.yaml
kubectl get pods
kubectl logs adapter-demo -c log-adapter
```

## Container Runtime Exploration

### Identifying the Container Runtime

The container runtime is the software responsible for running containers:

```bash
# Check the container runtime used by your cluster
kubectl get nodes -o wide
# Look for the "Container Runtime Version" field

# If using minikube, check the container runtime directly
minikube ssh
ps aux | grep kubelet | grep container-runtime
```

### Exploring containerd

If your cluster uses containerd (the default since Kubernetes 1.24):

```bash
# For minikube, SSH into the node
minikube ssh

# Check containerd status
sudo systemctl status containerd

# List running containers with crictl (CRI command-line tool)
sudo crictl ps

# List container images
sudo crictl images

# Get container details
CONTAINER_ID=$(sudo crictl ps | grep nginx | awk '{print $1}')
sudo crictl inspect $CONTAINER_ID
```

### Exploring CRI-O

If your cluster uses CRI-O:

```bash
# Check CRI-O status
sudo systemctl status crio

# List running containers
sudo crictl ps

# List pods
sudo crictl pods

# List images
sudo crictl images
```

### Comparing Container Runtimes

Create a script to gather information about different container runtimes:

```bash
#!/bin/bash
# container-runtime-info.sh

cat << EOF
Container Runtime Information
-----------------------------

1. Runtime details:
$(kubectl get nodes -o wide | grep -i "container-runtime")

2. Runtime processes:
$(ps aux | grep -E 'containerd|crio|dockerd' | grep -v grep)

3. Images available:
$(sudo crictl images 2>/dev/null || echo "Failed to get images with crictl")

4. Running containers:
$(sudo crictl ps 2>/dev/null || echo "Failed to get containers with crictl")

EOF
```

Make the script executable and run it:

```bash
chmod +x container-runtime-info.sh
./container-runtime-info.sh
```

## API and Architecture Exploration

### Exploring the Kubernetes API

The Kubernetes API is the foundation of the declarative model:

```bash
# Start the kubectl proxy to access the API
kubectl proxy --port=8080 &

# Explore API endpoints
curl http://localhost:8080/api/
curl http://localhost:8080/apis/
curl http://localhost:8080/apis/apps/v1

# Get the available API versions
kubectl api-versions

# List API resources
kubectl api-resources
```

### Understanding Resource Relationships

Create a deployment to observe how resources relate to one another:

```bash
# Create a deployment
kubectl create deployment nginx --image=nginx --replicas=2

# Observe the resource hierarchy
kubectl get deployments
kubectl get replicasets
kubectl get pods

# Use owner references to see relationships
kubectl get pod <pod-name> -o jsonpath='{.metadata.ownerReferences}'
```

### Experimenting with the Reconciliation Loop

Kubernetes continuously reconciles desired state with actual state:

```bash
# Create a deployment with 2 replicas
kubectl create deployment reconcile-demo --image=nginx --replicas=2

# Watch the pods
kubectl get pods -l app=reconcile-demo -w &

# Manually delete a pod and watch it get recreated
POD_NAME=$(kubectl get pods -l app=reconcile-demo -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $POD_NAME

# Change the desired state
kubectl scale deployment reconcile-demo --replicas=4

# Watch the actual state converge with the desired state
kubectl get pods -l app=reconcile-demo
```

### Creating a Custom Controller Example

To understand the controller pattern better, let's create a simple bash-based controller that watches for pods and logs their status changes:

```bash
#!/bin/bash
# simple-controller.sh

echo "Simple Pod Watcher Controller"
echo "-----------------------------"
echo "This controller watches pods and logs status changes"
echo

# Initialize the known state
declare -A pod_states

# Get initial pod states
function get_initial_state() {
  local pods=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}={.status.phase};{end}')
  
  IFS=';' read -ra PODS_ARRAY <<< "$pods"
  for pod in "${PODS_ARRAY[@]}"; do
    if [[ ! -z "$pod" ]]; then
      pod_states[$pod]=$(echo $pod | cut -d= -f2)
      echo "Initial state: $pod"
    fi
  done
}

# Controller reconciliation loop
function controller_loop() {
  while true; do
    # Get current state
    local pods=$(kubectl get pods --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}={.status.phase};{end}')
    
    IFS=';' read -ra PODS_ARRAY <<< "$pods"
    for pod in "${PODS_ARRAY[@]}"; do
      if [[ ! -z "$pod" ]]; then
        pod_id=$(echo $pod | cut -d= -f1)
        current_state=$(echo $pod | cut -d= -f2)
        
        # If this is a new pod or the state has changed
        if [[ -z "${pod_states[$pod_id]}" ]]; then
          echo "$(date): New pod detected: $pod_id in state $current_state"
          pod_states[$pod_id]=$current_state
        elif [[ "${pod_states[$pod_id]}" != "$current_state" ]]; then
          echo "$(date): Pod $pod_id changed state from ${pod_states[$pod_id]} to $current_state"
          pod_states[$pod_id]=$current_state
        fi
      fi
    done
    
    # Check for deleted pods
    for pod_id in "${!pod_states[@]}"; do
      found=false
      for pod in "${PODS_ARRAY[@]}"; do
        if [[ ! -z "$pod" && "$pod_id" == "$(echo $pod | cut -d= -f1)" ]]; then
          found=true
          break
        fi
      done
      
      if [[ "$found" == "false" ]]; then
        echo "$(date): Pod $pod_id was deleted (was in state ${pod_states[$pod_id]})"
        unset pod_states[$pod_id]
      fi
    done
    
    sleep 2
  done
}

# Main execution
get_initial_state
controller_loop
```

Make the script executable and run it:

```bash
chmod +x simple-controller.sh
./simple-controller.sh
```

In another terminal, create and delete pods to see the controller in action:

```bash
kubectl run test-pod1 --image=nginx
kubectl run test-pod2 --image=busybox -- sleep 30
kubectl delete pod test-pod1
```

### Understanding StatefulSets

StatefulSets provide stable network identities and persistent storage:

```bash
# Create a simple StatefulSet
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  ports:
  - port: 80
    name: web
  clusterIP: None
  selector:
    app: nginx
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: "nginx"
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
        image: nginx
        ports:
        - containerPort: 80
          name: web
        volumeMounts:
        - name: www
          mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
  - metadata:
      name: www
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 1Gi
EOF

# Observe the StatefulSet behavior
kubectl get statefulset
kubectl get pods -l app=nginx
# Notice the ordered naming: web-0, web-1, web-2

# Scale the StatefulSet and observe the ordered creation/deletion
kubectl scale statefulset web --replicas=5
kubectl get pods -l app=nginx -w

kubectl scale statefulset web --replicas=2
kubectl get pods -l app=nginx -w
# Notice pods are deleted in reverse order
```

## Advanced: Implementing Level-Triggered Architecture

This script demonstrates the level-triggered architecture used by Kubernetes controllers:

```bash
#!/bin/bash
# level-triggered-controller.sh

# Define desired state
DESIRED_REPLICAS=3
APP_NAME="level-demo"
IMAGE_NAME="nginx"

function create_pod() {
  local pod_num=$1
  kubectl run $APP_NAME-$pod_num --labels="app=$APP_NAME" --image=$IMAGE_NAME
}

function delete_pod() {
  local pod_name=$1
  kubectl delete pod $pod_name --wait=false
}

function get_current_replicas() {
  kubectl get pods -l app=$APP_NAME --no-headers | wc -l
}

function reconcile() {
  echo "$(date): Starting reconciliation loop"
  
  # Get current state
  current_replicas=$(get_current_replicas)
  echo "Current state: $current_replicas replicas"
  echo "Desired state: $DESIRED_REPLICAS replicas"
  
  # Compare current state to desired state
  if [ "$current_replicas" -lt "$DESIRED_REPLICAS" ]; then
    # Need to scale up
    to_create=$(($DESIRED_REPLICAS - $current_replicas))
    echo "Scaling up: Creating $to_create new pods"
    
    for i in $(seq 1 $to_create); do
      pod_num=$(($current_replicas + $i))
      echo "Creating pod $APP_NAME-$pod_num"
      create_pod $pod_num
    done
  elif [ "$current_replicas" -gt "$DESIRED_REPLICAS" ]; then
    # Need to scale down
    to_delete=$(($current_replicas - $DESIRED_REPLICAS))
    echo "Scaling down: Deleting $to_delete pods"
    
    pods_to_delete=$(kubectl get pods -l app=$APP_NAME --no-headers | tail -n $to_delete | awk '{print $1}')
    for pod in $pods_to_delete; do
      echo "Deleting pod $pod"
      delete_pod $pod
    done
  else
    echo "System is in desired state: $current_replicas/$DESIRED_REPLICAS replicas"
  fi
}

# Clean up any existing resources
kubectl delete pods -l app=$APP_NAME 2>/dev/null

# Initial setup
echo "Setting up initial state"
for i in $(seq 1 $DESIRED_REPLICAS); do
  create_pod $i
done

# Main reconciliation loop
while true; do
  echo "--------------------------"
  reconcile
  sleep 10
  
  # Randomly adjust desired state to demonstrate reconciliation
  if [ $(($RANDOM % 3)) -eq 0 ]; then
    NEW_REPLICAS=$(($RANDOM % 5 + 1))
    echo "🔄 Changing desired state to $NEW_REPLICAS replicas"
    DESIRED_REPLICAS=$NEW_REPLICAS
  fi
  
  # Randomly delete a pod to simulate a failure
  if [ $(($RANDOM % 4)) -eq 0 ]; then
    pod_to_kill=$(kubectl get pods -l app=$APP_NAME --no-headers | shuf -n 1 | awk '{print $1}')
    if [ ! -z "$pod_to_kill" ]; then
      echo "🔄 Simulating pod failure by deleting $pod_to_kill"
      delete_pod $pod_to_kill
    fi
  fi
done
```

Make it executable and run it:

```bash
chmod +x level-triggered-controller.sh
./level-triggered-controller.sh
```

This demonstration shows how Kubernetes continuously reconciles the desired state with the actual state, handling both manual changes and automated adjustments.

## Conclusion

Through these practical implementations, you can better understand the core architectural concepts of Kubernetes:

1. **Control Plane & Node Components**: The components that make up the distributed system
2. **Container Runtimes**: The underlying technology for running containers
3. **Design Patterns**: Common patterns for solving containerized application challenges
4. **Kubernetes API**: The foundation of the declarative configuration model
5. **Level-Triggered Architecture**: The reconciliation loop that drives Kubernetes' self-healing capabilities

These practical exercises complement the theoretical understanding from Chapter 1 and provide a hands-on foundation for the more advanced topics in the following chapters.
