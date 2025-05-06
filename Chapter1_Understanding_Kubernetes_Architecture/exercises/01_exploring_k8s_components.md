# Exercise 1: Exploring Kubernetes Architecture Components

In this exercise, we'll explore the key components of a Kubernetes cluster to understand the architecture in practice.

## Prerequisites

- A working Kubernetes cluster (minikube, kind, or a cloud-based cluster)
- kubectl CLI installed and configured
- Basic understanding of command line operations

## Exercise Goals

- Identify and examine control plane components
- Explore node components and their functions
- Understand the communication patterns between components
- Visualize the Kubernetes architecture in action

## Part 1: Examining Control Plane Components

### 1. Checking API Server Health

The API server is the central management entity for the entire cluster. Let's examine it:

```bash
# For minikube
minikube ssh -- docker ps | grep kube-apiserver

# For standard Kubernetes clusters
kubectl get pods -n kube-system | grep kube-apiserver
```

### 2. Exploring etcd - The Cluster State Store

```bash
# For minikube
minikube ssh -- docker ps | grep etcd

# For standard clusters
kubectl get pods -n kube-system | grep etcd
```

To observe etcd's role, let's create a simple resource and watch it get stored:

```bash
# Create a deployment
kubectl create deployment nginx --image=nginx

# Watch the events (these represent state changes being recorded)
kubectl get events --sort-by=.metadata.creationTimestamp
```

### 3. Examining Controller Manager and Scheduler

```bash
# List controller manager and scheduler pods
kubectl get pods -n kube-system | grep -E 'controller-manager|scheduler'

# View scheduler logs
kubectl logs -n kube-system $(kubectl get pods -n kube-system | grep scheduler | awk '{print $1}')
```

## Part 2: Understanding Node Components

### 1. Examining kubelet

The kubelet is the primary node agent that communicates with the API server.

```bash
# For minikube
minikube ssh -- ps aux | grep kubelet

# For standard clusters, check kubelet status on worker nodes
kubectl get nodes
```

### 2. Exploring kube-proxy

```bash
# Check kube-proxy pods (one per node)
kubectl get pods -n kube-system | grep kube-proxy

# Examine kube-proxy configuration
kubectl describe daemonset kube-proxy -n kube-system
```

### 3. Container Runtime Identification

```bash
# For minikube
minikube ssh -- docker info

# For other clusters
kubectl get nodes -o wide
```

## Part 3: Communication Flow Demonstration

Let's visualize the communication pattern when deploying an application:

```bash
# Create a deployment and watch the events
kubectl create deployment demo --image=nginx --replicas=2

# Watch the events to see the control flow
kubectl get events --sort-by=.metadata.creationTimestamp

# See how the scheduler assigned pods to nodes
kubectl get pods -o wide
```

## Part 4: API Server Interaction Experiment

Every operation in Kubernetes goes through the API server. Let's examine this:

```bash
# Enable verbose output to see API server interaction
kubectl get pods -v=8

# Run a simple kubectl command with curl equivalent
kubectl get pods -v=8 --output-curl-file=api-request.txt

# Examine the generated curl command
cat api-request.txt
```

## Part 5: Self-Healing Demonstration

One of Kubernetes' key features is self-healing. Let's demonstrate:

```bash
# Get the pod name for our deployment
POD_NAME=$(kubectl get pods | grep demo | awk '{print $1}' | head -1)

# Delete the pod and watch Kubernetes recreate it
kubectl delete pod $POD_NAME

# Watch as a new pod is automatically created
kubectl get pods -w
```

## Part 6: Analysis and Reflection

After completing the hands-on exploration, consider these questions:

1. How does information flow from the API server to the kubelet?
2. What is the role of etcd in maintaining cluster state?
3. How do controllers implement the reconciliation loop pattern?
4. What would happen if the scheduler were temporarily unavailable?
5. How does the control plane maintain high availability in production environments?

## Advanced Challenge

Create a diagram mapping the communication flow observed during your exploration:
1. User submits a request via kubectl
2. API server validates and persists to etcd
3. Controller notices the change
4. Scheduler assigns to a node
5. Kubelet creates the pod
6. Container runtime starts containers

Use a diagramming tool like draw.io, Mermaid, or even a simple text diagram, and save it to this directory.

## Conclusion

Through this exercise, you've experienced firsthand how the different Kubernetes architectural components work together to manage containerized applications. This foundation will help you better understand the more complex concepts in the following chapters.