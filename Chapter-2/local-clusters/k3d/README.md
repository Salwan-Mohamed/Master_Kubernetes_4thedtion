# k3d: Lightweight Kubernetes with k3s

k3d is a wrapper tool that facilitates running [k3s](https://k3s.io/) (a lightweight, certified Kubernetes distribution) in Docker. It's designed to be fast, lightweight, and easy to use, making it perfect for local development, testing, and CI/CD environments.

## Features

- Extremely lightweight and fast to start (usually under 30 seconds)
- Low resource consumption - works well on machines with limited resources
- Based on Rancher's k3s (CNCF-certified lightweight Kubernetes)
- Multi-node clusters in Docker containers
- Built-in support for load balancing and registry
- Supports custom registries
- Integrated with k3s features (SQLite storage backend instead of etcd)
- Excellent for CI/CD pipelines
- Cross-platform (Linux, macOS, Windows)

## Installation

### macOS

```bash
brew install k3d
```

### Linux

```bash
curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash
```

### Windows

```bash
choco install k3d
```

## Basic Commands

### Creating Clusters

```bash
# Create a default cluster
k3d cluster create

# Create a cluster with a specific name
k3d cluster create my-cluster

# Create a cluster with 3 worker nodes
k3d cluster create my-cluster --agents 3

# Create a cluster with multiple server nodes (control plane)
k3d cluster create ha-cluster --servers 3
```

### Interacting with Clusters

```bash
# List clusters
k3d cluster list

# Stop a cluster
k3d cluster stop my-cluster

# Start a cluster
k3d cluster start my-cluster

# Delete a cluster
k3d cluster delete my-cluster
```

## Advanced Usage

### Port Mapping

k3d makes it easy to map ports from the host to the cluster:

```bash
# Map host port 8080 to port 80 on the load balancer
k3d cluster create my-cluster -p "8080:80@loadbalancer"

# Map host port 8443 to port 443 on the load balancer
k3d cluster create my-cluster -p "8443:443@loadbalancer"

# Map multiple ports
k3d cluster create my-cluster -p "8080:80@loadbalancer" -p "8443:443@loadbalancer"
```

### Registry Integration

k3d can create and connect to local registries:

```bash
# Create a local registry
k3d registry create my-registry.localhost --port 5000

# Create a cluster and connect it to the registry
k3d cluster create my-cluster --registry-use k3d-my-registry.localhost:5000
```

### Multi-Server (HA) Configuration

```bash
# Create a HA cluster with 3 server nodes and 3 worker nodes
k3d cluster create ha-cluster --servers 3 --agents 3
```

### Custom Configuration with YAML

Create a file called `k3d-config.yaml`:

```yaml
apiVersion: k3d.io/v1alpha2
kind: Simple
name: advanced-config
servers: 1
agents: 2
kubeAPI:
  host: "k3d.localhost"
  hostIP: "127.0.0.1"
  hostPort: "6445"
ports:
  - port: 8080:80
    nodeFilters:
      - loadbalancer
options:
  k3d:
    wait: true
    timeout: "60s"
    disableLoadbalancer: false
    disableImageVolume: false
    disableRollback: false
  k3s:
    extraServerArgs:
      - --tls-san=k3d.localhost
    extraAgentArgs: []
  kubeconfig:
    updateDefaultKubeconfig: true
    switchCurrentContext: true
```

Apply the configuration:

```bash
k3d cluster create --config k3d-config.yaml
```

## Volume Handling

### Host Path Volumes

```bash
# Create a cluster with a host path volume
k3d cluster create my-cluster \
  --volume /path/on/host:/path/in/node@all
```

### Named Volumes

```bash
# Create a cluster with named volumes
k3d cluster create my-cluster \
  --volume my-vol:/path/in/node@all
```

## Working with Docker Images

```bash
# Build a local Docker image
docker build -t my-app:latest .

# Import the image into the k3d cluster
k3d image import my-app:latest -c my-cluster
```

## Practical Example: Deploying an Application with Ingress

This example demonstrates a complete workflow with k3d:

1. Create a cluster with port mapping:

```bash
k3d cluster create demo -p "8080:80@loadbalancer" --agents 2
```

2. Deploy a simple application:

```bash
kubectl create deployment nginx --image=nginx --replicas=2
kubectl create service clusterip nginx --tcp=80:80
```

3. Create an ingress:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx
  annotations:
    ingress.kubernetes.io/ssl-redirect: "false"
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx
            port:
              number: 80
EOF
```

4. Access the application:

```bash
curl http://localhost:8080
```

## Comparison with Other Local Kubernetes Solutions

| Feature | k3d | Minikube | KinD |
|---------|-----|----------|------|
| Startup Speed | Very Fast (<30s) | Slow (2-5 mins) | Fast (1-2 mins) |
| Resource Usage | Low | High | Medium |
| Multi-node | Yes | No | Yes |
| HA Support | Yes | No | Yes |
| Container Runtime | containerd | Multiple | containerd |
| Registry Integration | Built-in | Add-on | Manual |
| Load Balancer | Built-in | Tunnel | Manual |
| Storage Backend | SQLite | etcd | etcd |
| Used for | Development | Development | Testing K8s |

## Troubleshooting

### Common Issues

1. **Port conflicts**: If you get port binding errors:
   ```bash
   k3d cluster create demo -p "8081:80@loadbalancer"  # Use a different port
   ```

2. **Registry connectivity issues**:
   - Check Docker network settings
   - Ensure registry hostname resolution is properly configured

3. **Node communication issues**:
   - Check Docker networking settings
   - Ensure container-to-container communication is allowed

### Debugging Tips

```bash
# View k3d logs
k3d cluster list
docker logs k3d-demo-server-0

# Get cluster information
kubectl cluster-info

# Check node status
kubectl get nodes
```

## Performance Tips

1. Disable features you don't need:
   ```bash
   k3d cluster create --k3s-arg "--disable=traefik,servicelb,metrics-server@server:0"
   ```

2. Limit resource allocation for development environments:
   ```bash
   k3d cluster create --k3s-arg "--kubelet-arg=eviction-hard=imagefs.available<1%,nodefs.available<1%@server:0"
   ```

3. Use a local registry to avoid repeated downloads

## Cleanup

```bash
# Delete a specific cluster
k3d cluster delete my-cluster

# Delete all clusters
k3d cluster delete --all

# Delete registry
k3d registry delete my-registry.localhost
```

## Next Steps

- Explore [k3d's official documentation](https://k3d.io/stable/)
- Try integrating k3d into CI/CD pipelines
- Experiment with k3s-specific features
- Test application deployments across multiple nodes
