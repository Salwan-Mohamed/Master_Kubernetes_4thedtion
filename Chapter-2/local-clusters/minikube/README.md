# Minikube: Single-Node Kubernetes Cluster

Minikube is an official Kubernetes SIG project that creates a single-node Kubernetes cluster on your local machine, primarily designed for development and testing purposes.

## Features

- Easy installation and setup
- Supports multiple container runtimes (Docker, containerd, CRI-O)
- Cross-platform support (Windows, macOS, Linux)
- Addons for common Kubernetes services
- Support for persistence via hostPath
- Builtin support for ingress, dashboard, and metrics
- Easy service access via minikube service command

## Installation

### macOS

```bash
brew install minikube
```

### Linux

```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
```

### Windows

```bash
choco install minikube
```

Or download the executable from [GitHub Releases](https://github.com/kubernetes/minikube/releases).

## Basic Commands

### Starting a Cluster

```bash
# Start with default settings
minikube start

# Start with specific Kubernetes version
minikube start --kubernetes-version=v1.23.0

# Allocate more resources
minikube start --cpus=4 --memory=8192

# Use a different VM driver
minikube start --driver=virtualbox

# Use a different container runtime
minikube start --container-runtime=containerd
```

### Managing the Cluster

```bash
# Check status
minikube status

# Stop the cluster
minikube stop

# Delete the cluster
minikube delete

# SSH into the cluster
minikube ssh

# Dashboard access
minikube dashboard
```

### Addons

```bash
# List addons
minikube addons list

# Enable an addon
minikube addons enable ingress

# Disable an addon
minikube addons disable dashboard
```

### Accessing Services

```bash
# Get the URL for a service
minikube service --url <service-name>

# Open a service in the default browser
minikube service <service-name>

# Enable access to services of type LoadBalancer
minikube tunnel
```

## Advanced Usage

### Working with Multiple Clusters

```bash
# Create a second cluster with a different profile
minikube start -p cluster2

# Switch profiles
minikube profile cluster2

# List profiles
minikube profile list
```

### Working with Docker Images

```bash
# Point your terminal to use the docker daemon inside minikube
eval $(minikube docker-env)

# Build an image using the minikube docker daemon
docker build -t my-image:v1 .

# Revert to using your host's docker daemon
eval $(minikube docker-env -u)
```

## Practical Example: Deploying a Sample Application

```bash
# Create a deployment
kubectl create deployment hello-minikube --image=k8s.gcr.io/echoserver:1.10

# Expose the deployment as a service
kubectl expose deployment hello-minikube --type=NodePort --port=8080

# Get the URL to access the service
minikube service hello-minikube --url

# Test the application
curl $(minikube service hello-minikube --url)
```

## Troubleshooting

### Common Issues

1. **VM or driver issues**: If you encounter problems with your hypervisor, try switching to another:
   ```bash
   minikube start --driver=virtualbox
   ```

2. **Resource constraints**: If your cluster fails due to resource issues, allocate more:
   ```bash
   minikube start --cpus=4 --memory=8192
   ```

3. **Proxy issues**: If you're behind a corporate proxy:
   ```bash
   minikube start --docker-env HTTP_PROXY=http://proxy-url:port
   ```

4. **Dashboard not working**: Ensure it's enabled:
   ```bash
   minikube addons enable dashboard
   ```

### Getting Logs

```bash
# View minikube logs
minikube logs

# View logs for a specific component
minikube logs --problems
```

## Performance Tips

1. Use the native driver for your platform when possible
2. Allocate sufficient resources based on your workload
3. Consider using a local registry for image management
4. Reuse the same cluster for multiple deployments to avoid startup times

## Cleanup

```bash
# Stop the cluster (retains state)
minikube stop

# Delete the cluster (removes all state)
minikube delete

# Delete all clusters
minikube delete --all
```

## Next Steps

- Explore [minikube's official documentation](https://minikube.sigs.k8s.io/docs/)
- Try deploying more complex applications
- Experiment with different addons
- Practice configuring persistent volumes
