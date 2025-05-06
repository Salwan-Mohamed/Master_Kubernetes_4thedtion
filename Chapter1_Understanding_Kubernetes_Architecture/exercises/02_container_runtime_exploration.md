# Exercise 2: Container Runtime Exploration

This exercise explores the container runtimes used in Kubernetes and how they interact with the kubelet through the Container Runtime Interface (CRI).

## Prerequisites

- Access to a Kubernetes cluster (minikube, kind, or cloud-based)
- kubectl CLI installed and configured
- Basic understanding of containers and runtime concepts

## Exercise Goals

- Identify the container runtime used in your cluster
- Understand the CRI architecture
- Explore runtime-specific commands and features
- Compare different container runtimes

## Part 1: Identifying Your Container Runtime

### 1. Check Node Runtime Information

```bash
# Get detailed node information
kubectl get nodes -o wide

# Look for the "Container Runtime Version" field in node description
kubectl describe node <node-name> | grep "Container Runtime Version"
```

### 2. Examine kubelet Configuration

```bash
# For minikube
minikube ssh -- cat /var/lib/kubelet/config.yaml | grep -A5 containerRuntime

# For standard clusters (if you have SSH access to nodes)
ssh <node-ip> 'cat /var/lib/kubelet/config.yaml | grep -A5 containerRuntime'

# Alternatively, for managed clusters without SSH access
kubectl get pods -n kube-system -l component=kubelet -o yaml | grep container
```

## Part 2: Understanding CRI Socket

The CRI socket is the Unix socket that kubelet uses to communicate with the container runtime.

### 1. Find the CRI Socket Path

```bash
# For minikube
minikube ssh -- ps aux | grep kubelet | grep container-runtime

# For standard clusters (if you have SSH access)
ssh <node-ip> 'ps aux | grep kubelet | grep container-runtime'
```

### 2. Examine the Socket

```bash
# For minikube
minikube ssh -- ls -la /var/run/containerd/containerd.sock

# For standard clusters with containerd
ssh <node-ip> 'ls -la /var/run/containerd/containerd.sock'

# For CRI-O
ssh <node-ip> 'ls -la /var/run/crio/crio.sock'
```

## Part 3: Exploring containerd (If Your Cluster Uses containerd)

### 1. List Running Containers with containerd CLI

```bash
# For minikube
minikube ssh -- sudo crictl ps

# For standard clusters
ssh <node-ip> 'sudo crictl ps'
```

### 2. Examine Container Details

```bash
# Get a container ID first
CONTAINER_ID=$(ssh <node-ip> 'sudo crictl ps | grep nginx | awk "{print \$1}"')

# Inspect the container
ssh <node-ip> "sudo crictl inspect $CONTAINER_ID"
```

### 3. Explore Image Management

```bash
# List images
ssh <node-ip> 'sudo crictl images'

# Pull a new image
ssh <node-ip> 'sudo crictl pull nginx:alpine'
```

## Part 4: Exploring CRI-O (If Your Cluster Uses CRI-O)

### 1. Check CRI-O Status

```bash
ssh <node-ip> 'sudo systemctl status crio'
```

### 2. List Containers and Pods

```bash
# List pods
ssh <node-ip> 'sudo crictl pods'

# List containers
ssh <node-ip> 'sudo crictl ps'
```

### 3. Examine CRI-O Configuration

```bash
ssh <node-ip> 'sudo cat /etc/crio/crio.conf'
```

## Part 5: Container Runtime Implementation Exercise

Let's create a script to check which CRI implementation is being used and provide appropriate commands for that runtime.

Create a file called `cri-inspector.sh`:

```bash
#!/bin/bash

NODE_NAME=$(kubectl get nodes -o name | head -1 | cut -d'/' -f2)
RUNTIME=$(kubectl describe node $NODE_NAME | grep "Container Runtime Version" | awk '{print $4}')

echo "Detected container runtime: $RUNTIME"

case $RUNTIME in
  containerd*)
    echo "Commands for containerd:"
    echo "  List containers: crictl ps"
    echo "  List images: crictl images"
    echo "  Inspect container: crictl inspect <container-id>"
    echo "  View logs: crictl logs <container-id>"
    ;;
  cri-o*)
    echo "Commands for CRI-O:"
    echo "  List containers: crictl ps"
    echo "  List images: crictl images"
    echo "  Inspect container: crictl inspect <container-id>"
    echo "  View logs: crictl logs <container-id>"
    ;;
  docker*)
    echo "Commands for Docker:"
    echo "  List containers: docker ps"
    echo "  List images: docker images"
    echo "  Inspect container: docker inspect <container-id>"
    echo "  View logs: docker logs <container-id>"
    ;;
  *)
    echo "Unknown runtime: $RUNTIME"
    ;;
esac
```

Make it executable and run it:

```bash
chmod +x cri-inspector.sh
./cri-inspector.sh
```

## Part 6: CRI Simulation

Let's simulate the CRI's ImageService and RuntimeService interfaces to understand how Kubernetes interacts with container runtimes.

Create a file called `cri-simulator.go`:

```go
package main

import (
	"fmt"
)

// Simplified CRI interfaces
type ImageService interface {
	ListImages()
	PullImage(image string)
	RemoveImage(image string)
}

type RuntimeService interface {
	CreateContainer(podID, name, image string)
	StartContainer(id string)
	StopContainer(id string)
	RemoveContainer(id string)
	ListContainers()
}

// Containerd implementation
type ContainerdRuntime struct{}

func (c *ContainerdRuntime) ListImages() {
	fmt.Println("[Containerd] Listing images via containerd API")
}

func (c *ContainerdRuntime) PullImage(image string) {
	fmt.Printf("[Containerd] Pulling image %s via containerd API\n", image)
}

func (c *ContainerdRuntime) RemoveImage(image string) {
	fmt.Printf("[Containerd] Removing image %s via containerd API\n", image)
}

func (c *ContainerdRuntime) CreateContainer(podID, name, image string) {
	fmt.Printf("[Containerd] Creating container %s with image %s in pod %s\n", name, image, podID)
}

func (c *ContainerdRuntime) StartContainer(id string) {
	fmt.Printf("[Containerd] Starting container %s\n", id)
}

func (c *ContainerdRuntime) StopContainer(id string) {
	fmt.Printf("[Containerd] Stopping container %s\n", id)
}

func (c *ContainerdRuntime) RemoveContainer(id string) {
	fmt.Printf("[Containerd] Removing container %s\n", id)
}

func (c *ContainerdRuntime) ListContainers() {
	fmt.Println("[Containerd] Listing containers via containerd API")
}

// CRI-O implementation
type CrioRuntime struct{}

func (c *CrioRuntime) ListImages() {
	fmt.Println("[CRI-O] Listing images via CRI-O API")
}

func (c *CrioRuntime) PullImage(image string) {
	fmt.Printf("[CRI-O] Pulling image %s via CRI-O API\n", image)
}

func (c *CrioRuntime) RemoveImage(image string) {
	fmt.Printf("[CRI-O] Removing image %s via CRI-O API\n", image)
}

func (c *CrioRuntime) CreateContainer(podID, name, image string) {
	fmt.Printf("[CRI-O] Creating container %s with image %s in pod %s\n", name, image, podID)
}

func (c *CrioRuntime) StartContainer(id string) {
	fmt.Printf("[CRI-O] Starting container %s\n", id)
}

func (c *CrioRuntime) StopContainer(id string) {
	fmt.Printf("[CRI-O] Stopping container %s\n", id)
}

func (c *CrioRuntime) RemoveContainer(id string) {
	fmt.Printf("[CRI-O] Removing container %s\n", id)
}

func (c *CrioRuntime) ListContainers() {
	fmt.Println("[CRI-O] Listing containers via CRI-O API")
}

// Kubelet simulation
type Kubelet struct {
	runtime RuntimeService
	images  ImageService
}

func (k *Kubelet) RunPod(podID, containerName, image string) {
	fmt.Println("Kubelet: Running pod workflow")
	k.images.PullImage(image)
	k.runtime.CreateContainer(podID, containerName, image)
	k.runtime.StartContainer(containerName)
	fmt.Println("Kubelet: Pod started successfully")
}

func (k *Kubelet) StopPod(podID, containerName string) {
	fmt.Println("Kubelet: Stopping pod workflow")
	k.runtime.StopContainer(containerName)
	k.runtime.RemoveContainer(containerName)
	fmt.Println("Kubelet: Pod stopped successfully")
}

func main() {
	// Simulate with containerd
	fmt.Println("=== Simulation with containerd ===")
	containerdRT := &ContainerdRuntime{}
	kubeletWithContainerd := &Kubelet{
		runtime: containerdRT,
		images:  containerdRT,
	}
	kubeletWithContainerd.RunPod("pod-1", "nginx-1", "nginx:latest")
	containerdRT.ListContainers()
	kubeletWithContainerd.StopPod("pod-1", "nginx-1")

	fmt.Println("\n=== Simulation with CRI-O ===")
	crioRT := &CrioRuntime{}
	kubeletWithCrio := &Kubelet{
		runtime: crioRT,
		images:  crioRT,
	}
	kubeletWithCrio.RunPod("pod-2", "nginx-2", "nginx:latest")
	crioRT.ListContainers()
	kubeletWithCrio.StopPod("pod-2", "nginx-2")
}
```

Compile and run this Go program to see the CRI abstraction in action:

```bash
go run cri-simulator.go
```

## Part 7: Analysis and Reflection

After completing the hands-on exploration, consider these questions:

1. What are the advantages and disadvantages of the container runtime in your cluster?
2. How does the CRI abstract away the differences between container runtimes?
3. What would be involved in switching from one container runtime to another?
4. How does the container runtime isolation model affect security in your cluster?
5. What criteria would you use to select a container runtime for a production Kubernetes cluster?

## Advanced Challenge

Design a comparison matrix of different container runtimes (containerd, CRI-O, Docker + cri-dockerd) with the following criteria:
- Memory footprint
- Security features
- Compatibility with Kubernetes versions
- Ease of management
- Community support
- Special features

Use this information to make a recommendation for which container runtime would be best for:
1. A development environment
2. A high-security production environment
3. An edge computing scenario

## Conclusion

Through this exercise, you've explored how container runtimes integrate with Kubernetes through the CRI. Understanding this relationship is essential for efficient cluster management, troubleshooting, and optimization in production environments.