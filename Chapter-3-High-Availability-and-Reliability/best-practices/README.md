# High Availability Best Practices

## Introduction

Building reliable and highly available distributed systems is complex, but following proven best practices can significantly improve your success rate. This section provides practical guidance for implementing HA Kubernetes clusters.

> **Important Note**: You should only roll your own highly available Kubernetes cluster in very special cases. Most production environments should use managed services (GKE, EKS, AKS) or battle-tested tools built on kubeadm.

## Core Architecture Patterns

### 1. Highly Available Cluster Topologies

#### Stacked etcd Topology
**Most common HA setup - etcd runs on control plane nodes**

```yaml
# Control Plane Node Configuration
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
metadata:
  name: config
kubernetesVersion: v1.20.0
controlPlaneEndpoint: "loadbalancer.example.com:6443"
etcd:
  local:
    dataDir: "/var/lib/etcd"
    serverCertSANs:
    - "etcd1.example.com"
    - "etcd2.example.com"
    - "etcd3.example.com"
    peerCertSANs:
    - "etcd1.example.com"
    - "etcd2.example.com"
    - "etcd3.example.com"
networking:
  serviceSubnet: "10.96.0.0/12"
  podSubnet: "192.168.0.0/16"
apiServer:
  certSANs:
  - "kubernetes.example.com"
  - "loadbalancer.example.com"
  - "127.0.0.1"
  - "10.96.0.1"
```

#### External etcd Topology
**Separate etcd cluster for maximum reliability**

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
metadata:
  name: config
kubernetesVersion: v1.20.0
controlPlaneEndpoint: "loadbalancer.example.com:6443"
etcd:
  external:
    endpoints:
    - "https://etcd1.example.com:2379"
    - "https://etcd2.example.com:2379"
    - "https://etcd3.example.com:2379"
    caFile: "/etc/kubernetes/pki/etcd/ca.crt"
    certFile: "/etc/kubernetes/pki/apiserver-etcd-client.crt"
    keyFile: "/etc/kubernetes/pki/apiserver-etcd-client.key"
```

### 2. Node Reliability Configuration

#### SystemD Service Configuration
**Ensure critical services restart automatically**

```bash
# Enable automatic restart for Docker/containerd
sudo systemctl enable docker
sudo systemctl enable kubelet

# Configure kubelet service
sudo cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf << EOF
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
EnvironmentFile=-/etc/default/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
Restart=always
RestartSec=10s
EOF
```

#### Process Monitoring with Monit
**For non-systemd systems**

```bash
# Install monit
sudo apt-get install monit

# Configure monitoring
sudo cat > /etc/monit/conf.d/kubelet << EOF
check process kubelet with pidfile /var/run/kubelet.pid
  start program = "/bin/systemctl start kubelet"
  stop program = "/bin/systemctl stop kubelet"
  if failed port 10250 protocol http then restart
  if 3 restarts within 5 cycles then timeout
EOF

# Enable and start monit
sudo systemctl enable monit
sudo systemctl start monit
```

### 3. Cluster State Protection

#### etcd Clustering Setup
**Minimum 3 nodes for production**

```bash
# etcd cluster configuration for 3 nodes
# Node 1 (etcd1.example.com)
etcd --name etcd1 \
  --data-dir /var/lib/etcd \
  --listen-client-urls https://0.0.0.0:2379 \
  --advertise-client-urls https://etcd1.example.com:2379 \
  --listen-peer-urls https://0.0.0.0:2380 \
  --initial-advertise-peer-urls https://etcd1.example.com:2380 \
  --initial-cluster etcd1=https://etcd1.example.com:2380,etcd2=https://etcd2.example.com:2380,etcd3=https://etcd3.example.com:2380 \
  --initial-cluster-state new \
  --initial-cluster-token etcd-cluster-1

# Repeat for etcd2 and etcd3 with appropriate names and URLs
```

#### etcd Backup Strategy

```bash
#!/bin/bash
# etcd-backup.sh - Regular backup script

BACKUP_DIR="/backup/etcd/$(date +%Y%m%d)"
mkdir -p $BACKUP_DIR

# Create etcd snapshot
ETCDCTL_API=3 etcdctl snapshot save $BACKUP_DIR/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify backup
ETCDCTL_API=3 etcdctl snapshot status $BACKUP_DIR/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db

# Clean old backups (keep 7 days)
find /backup/etcd -type d -mtime +7 -exec rm -rf {} +
```

### 4. Data Protection with Velero

#### Velero Installation
```bash
# Install Velero CLI
wget https://github.com/vmware-tanzu/velero/releases/download/v1.7.0/velero-v1.7.0-linux-amd64.tar.gz
tar -xzf velero-v1.7.0-linux-amd64.tar.gz
sudo mv velero-v1.7.0-linux-amd64/velero /usr/local/bin/

# Install Velero in cluster (AWS example)
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.3.0 \
  --bucket velero-backups \
  --backup-location-config region=us-west-2 \
  --snapshot-location-config region=us-west-2 \
  --secret-file ./credentials-velero
```

#### Backup Configuration
```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: daily-backup
  namespace: velero
spec:
  includedNamespaces:
  - "*"
  excludedNamespaces:
  - kube-system
  - velero
  storageLocation: default
  ttl: 720h0m0s  # 30 days
  snapshotVolumes: true
---
apiVersion: velero.io/v1
kind: Schedule
metadata:
  name: daily-backup-schedule
  namespace: velero
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  template:
    includedNamespaces:
    - "*"
    excludedNamespaces:
    - kube-system
    - velero
    storageLocation: default
    ttl: 720h0m0s
```

### 5. API Server High Availability

#### Load Balancer Configuration
**HAProxy example for API server load balancing**

```bash
# /etc/haproxy/haproxy.cfg
global
    daemon

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    option httplog

frontend kubernetes-apiserver
    bind *:6443
    mode tcp
    option tcplog
    default_backend kubernetes-apiserver

backend kubernetes-apiserver
    mode tcp
    balance roundrobin
    option tcp-check
    server master1 10.0.1.10:6443 check
    server master2 10.0.1.11:6443 check
    server master3 10.0.1.12:6443 check
```

#### Nginx Load Balancer Alternative
```nginx
# /etc/nginx/nginx.conf
stream {
    upstream kubernetes {
        server 10.0.1.10:6443;
        server 10.0.1.11:6443;
        server 10.0.1.12:6443;
    }
    
    server {
        listen 6443;
        proxy_pass kubernetes;
    }
}
```

### 6. Leader Election Configuration

#### Scheduler Configuration
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-scheduler
  namespace: kube-system
spec:
  containers:
  - name: kube-scheduler
    image: k8s.gcr.io/kube-scheduler:v1.20.0
    command:
    - kube-scheduler
    - --bind-address=127.0.0.1
    - --leader-elect=true
    - --leader-elect-lease-duration=15s
    - --leader-elect-renew-deadline=10s
    - --leader-elect-retry-period=2s
    - --leader-elect-resource-lock=leases
    - --kubeconfig=/etc/kubernetes/scheduler.conf
    - --authentication-kubeconfig=/etc/kubernetes/scheduler.conf
    - --authorization-kubeconfig=/etc/kubernetes/scheduler.conf
```

#### Controller Manager Configuration
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-controller-manager
  namespace: kube-system
spec:
  containers:
  - name: kube-controller-manager
    image: k8s.gcr.io/kube-controller-manager:v1.20.0
    command:
    - kube-controller-manager
    - --bind-address=127.0.0.1
    - --leader-elect=true
    - --leader-elect-lease-duration=15s
    - --leader-elect-renew-deadline=10s
    - --leader-elect-retry-period=2s
    - --kubeconfig=/etc/kubernetes/controller-manager.conf
    - --authentication-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --authorization-kubeconfig=/etc/kubernetes/controller-manager.conf
    - --cluster-cidr=192.168.0.0/16
    - --service-cluster-ip-range=10.96.0.0/12
    - --allocate-node-cidrs=true
```

## Production-Ready Checklist

### Infrastructure Level
- [ ] **Multiple Availability Zones**: Distribute nodes across AZs
- [ ] **Network Redundancy**: Multiple network paths
- [ ] **Storage Redundancy**: Replicated persistent storage
- [ ] **Power Redundancy**: UPS and backup power sources
- [ ] **Hardware Diversity**: Avoid single vendor dependencies

### Kubernetes Level
- [ ] **Control Plane HA**: 3+ master nodes
- [ ] **etcd Clustering**: 3 or 5 node etcd cluster
- [ ] **Load Balancer**: API server load balancing
- [ ] **Leader Election**: Enabled for scheduler and controller-manager
- [ ] **Node Reliability**: Auto-restart critical services

### Application Level
- [ ] **Pod Replicas**: Multiple replicas for critical workloads
- [ ] **Health Checks**: Liveness and readiness probes
- [ ] **Resource Limits**: Prevent resource starvation
- [ ] **Pod Disruption Budgets**: Control voluntary disruptions
- [ ] **Anti-Affinity**: Spread replicas across nodes/zones

### Operational Level
- [ ] **Monitoring**: Comprehensive cluster monitoring
- [ ] **Alerting**: Proactive problem notification
- [ ] **Backup Strategy**: Regular backups with tested restore
- [ ] **Disaster Recovery**: Documented DR procedures
- [ ] **Chaos Engineering**: Regular failure testing

## Testing Your HA Setup

### Basic Validation Tests
```bash
#!/bin/bash
# ha-validation.sh - Basic HA validation

echo "Testing API server availability..."
for i in {1..10}; do
    kubectl get nodes > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "API server test $i: PASS"
    else
        echo "API server test $i: FAIL"
    fi
    sleep 2
done

echo "Testing etcd cluster health..."
ETCDCTL_API=3 etcdctl endpoint health \
  --cluster \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

echo "Testing pod scheduling..."
kubectl run test-pod --image=nginx --rm -it --restart=Never -- echo "Scheduling test: PASS"
```

### Failure Simulation
```bash
#!/bin/bash
# failure-simulation.sh - Simulate component failures

echo "Simulating master node failure..."
# Stop kubelet on one master node
ssh master1 'sudo systemctl stop kubelet'
sleep 30

# Verify cluster still functions
kubectl get nodes
kubectl get pods --all-namespaces

# Restart the node
ssh master1 'sudo systemctl start kubelet'
echo "Master node failure simulation complete"
```

## Common Pitfalls and Solutions

### ❌ Single Points of Failure
**Problem**: Critical components with no redundancy
**Solution**: Implement redundancy at every level

### ❌ Split-Brain Scenarios
**Problem**: Multiple components thinking they're the leader
**Solution**: Use proper quorum sizes (odd numbers) and leader election

### ❌ Cascading Failures
**Problem**: One failure triggering multiple failures
**Solution**: Circuit breakers, timeouts, and bulkhead patterns

### ❌ Untested Backup/Restore
**Problem**: Backups that don't work when needed
**Solution**: Regular backup testing and automated restore validation

## Cloud Provider Specific Considerations

### AWS
- Use multiple Availability Zones
- ELB for API server load balancing
- EBS snapshots for persistent volumes
- Auto Scaling Groups for node management

### GCP
- Multi-zone deployments
- Cloud Load Balancer
- Persistent Disk snapshots
- Managed Instance Groups

### Azure
- Availability Zones or Availability Sets
- Azure Load Balancer
- Managed Disks with snapshots
- Virtual Machine Scale Sets

## Next Steps

- [Scalability and Capacity Planning](../scalability/)
- [Performance Optimization](../performance/)
- [Autoscaling Configuration](../autoscaling/)
- [Testing at Scale](../testing/)

---

*Remember: High availability is not just about technology - it requires proper processes, monitoring, and regular testing to be effective.*