# Hardening Kubernetes

## Overview

Hardening Kubernetes is the process of securing the cluster against potential vulnerabilities and attacks. This involves securing the control plane, worker nodes, network, and implementing proper configuration management.

## Table of Contents

1. [Control Plane Hardening](#control-plane-hardening)
2. [Node Security](#node-security)
3. [etcd Security](#etcd-security)
4. [API Server Security](#api-server-security)
5. [Kubelet Security](#kubelet-security)
6. [Container Runtime Security](#container-runtime-security)
7. [Security Benchmarks](#security-benchmarks)

## Control Plane Hardening

### API Server Security

The Kubernetes API server is the gateway to your cluster and must be properly secured:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-apiserver
spec:
  containers:
  - command:
    - kube-apiserver
    # Enable audit logging
    - --audit-log-path=/var/log/audit.log
    - --audit-log-maxage=30
    - --audit-log-maxbackup=3
    - --audit-log-maxsize=100
    - --audit-policy-file=/etc/kubernetes/audit-policy.yaml
    
    # Disable insecure ports
    - --insecure-port=0
    
    # Enable admission controllers
    - --enable-admission-plugins=NodeRestriction,PodSecurityPolicy,ServiceAccount
    
    # TLS configuration
    - --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
    - --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
    - --client-ca-file=/etc/kubernetes/pki/ca.crt
    
    # RBAC authorization
    - --authorization-mode=Node,RBAC
    
    # Anonymous requests (disable in production)
    - --anonymous-auth=false
    
    # Request timeout
    - --request-timeout=300s
    
    # Enable profiling (disable in production)
    - --profiling=false
```

### Audit Policy Configuration

Create a comprehensive audit policy:

```yaml
# /etc/kubernetes/audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Log pod changes at RequestResponse level
- level: RequestResponse
  resources:
  - group: ""
    resources: ["pods"]
  
# Log secret access
- level: Request
  resources:
  - group: ""
    resources: ["secrets"]
    
# Log service account token requests
- level: Metadata
  resources:
  - group: ""
    resources: ["serviceaccounts/token"]
    
# Log metadata for all other requests
- level: Metadata
  omitStages:
  - RequestReceived
```

### etcd Security

Secure etcd, the key-value store for Kubernetes:

```yaml
# /etc/kubernetes/manifests/etcd.yaml
apiVersion: v1
kind: Pod
metadata:
  name: etcd
spec:
  containers:
  - command:
    - etcd
    # Client TLS
    - --cert-file=/etc/kubernetes/pki/etcd/server.crt
    - --key-file=/etc/kubernetes/pki/etcd/server.key
    - --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --client-cert-auth=true
    
    # Peer TLS
    - --peer-cert-file=/etc/kubernetes/pki/etcd/peer.crt
    - --peer-key-file=/etc/kubernetes/pki/etcd/peer.key
    - --peer-trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
    - --peer-client-cert-auth=true
    
    # Data encryption at rest
    - --encryption-provider-config=/etc/kubernetes/encryption-config.yaml
```

### Encryption at Rest Configuration

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <base64-encoded-32-byte-key>
  - identity: {}
```

## Node Security

### Kubelet Configuration

Secure kubelet on worker nodes:

```yaml
# /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration

# Authentication
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
    cacheTTL: 2m0s
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt

# Authorization
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s

# TLS configuration
tlsCertFile: /var/lib/kubelet/pki/kubelet.crt
tlsPrivateKeyFile: /var/lib/kubelet/pki/kubelet.key

# Read-only port (disable)
readOnlyPort: 0

# Event burst and QPS
eventBurst: 10
eventRecordQPS: 5

# Container runtime
containerRuntimeEndpoint: unix:///var/run/containerd/containerd.sock

# Security context
allowPrivileged: false

# Protect kernel defaults
protectKernelDefaults: true

# Log rotation
logRotation:
  maxSize: 10Mi
  maxFiles: 5
```

### Node Hardening Script

```bash
#!/bin/bash
# node-hardening.sh

echo "Starting Kubernetes node hardening..."

# Update system packages
sudo apt update && sudo apt upgrade -y

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Configure kernel parameters
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1

# Security hardening
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.icmp_ignore_bogus_error_responses = 1
kernel.dmesg_restrict = 1
EOF

sudo sysctl --system

# Configure firewall (UFW example)
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH
sudo ufw allow ssh

# Allow Kubernetes ports
sudo ufw allow 6443/tcp  # API server
sudo ufw allow 2379:2380/tcp  # etcd
sudo ufw allow 10250/tcp  # kubelet
sudo ufw allow 10251/tcp  # kube-scheduler
sudo ufw allow 10252/tcp  # kube-controller-manager
sudo ufw allow 30000:32767/tcp  # NodePort services

# Secure shared memory
echo "tmpfs /run/shm tmpfs defaults,noexec,nosuid,nodev,size=100M 0 0" | sudo tee -a /etc/fstab

# Configure audit logging
sudo mkdir -p /var/log/kubernetes
sudo chown root:root /var/log/kubernetes
sudo chmod 755 /var/log/kubernetes

echo "Node hardening completed. Please reboot the system."
```

## Container Runtime Security

### Containerd Configuration

```toml
# /etc/containerd/config.toml
version = 2

[plugins."io.containerd.grpc.v1.cri"]
  # Enable AppArmor
  [plugins."io.containerd.grpc.v1.cri".containerd]
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
        runtime_type = "io.containerd.runc.v2"
        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
          SystemdCgroup = true
          
  # Registry configuration
  [plugins."io.containerd.grpc.v1.cri".registry]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://registry-1.docker.io"]
```

### gVisor (runsc) Security Runtime

```yaml
# gvisor-runtime-class.yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
---
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  runtimeClassName: gvisor
  containers:
  - name: app
    image: nginx:alpine
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
```

## Security Benchmarks

### CIS Kubernetes Benchmark

Implement CIS (Center for Internet Security) benchmark recommendations:

```bash
#!/bin/bash
# cis-benchmark-check.sh

echo "Running CIS Kubernetes Benchmark checks..."

# Check 1.1.1 - Ensure that the API server pod specification file permissions are set to 644 or more restrictive
API_SERVER_FILE="/etc/kubernetes/manifests/kube-apiserver.yaml"
if [ -f "$API_SERVER_FILE" ]; then
    PERMS=$(stat -c "%a" "$API_SERVER_FILE")
    if [ "$PERMS" -le 644 ]; then
        echo "✓ API server pod specification file permissions are secure ($PERMS)"
    else
        echo "✗ API server pod specification file permissions are too permissive ($PERMS)"
    fi
fi

# Check 1.2.1 - Ensure that the --anonymous-auth argument is set to false
if pgrep -f kube-apiserver | xargs ps -p | grep -q "anonymous-auth=false"; then
    echo "✓ Anonymous authentication is disabled"
else
    echo "✗ Anonymous authentication should be disabled"
fi

# Check 1.2.6 - Ensure that the --insecure-port argument is set to 0
if pgrep -f kube-apiserver | xargs ps -p | grep -q "insecure-port=0"; then
    echo "✓ Insecure port is disabled"
else
    echo "✗ Insecure port should be disabled"
fi

# Check 2.1 - Ensure that the --cert-file and --key-file arguments are set as appropriate
if pgrep -f etcd | xargs ps -p | grep -q "cert-file" && pgrep -f etcd | xargs ps -p | grep -q "key-file"; then
    echo "✓ etcd TLS certificates are configured"
else
    echo "✗ etcd TLS certificates should be configured"
fi

echo "CIS benchmark check completed."
```

### Kube-bench Integration

```yaml
# kube-bench-job.yaml
apiVersion: v1
kind: Job
metadata:
  name: kube-bench
spec:
  template:
    spec:
      hostPID: true
      nodeSelector:
        kubernetes.io/os: linux
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      containers:
      - name: kube-bench
        image: aquasec/kube-bench:latest
        command: ["kube-bench"]
        args: ["--version", "1.23"]
        volumeMounts:
        - name: var-lib-etcd
          mountPath: /var/lib/etcd
          readOnly: true
        - name: var-lib-kubelet
          mountPath: /var/lib/kubelet
          readOnly: true
        - name: etc-systemd
          mountPath: /etc/systemd
          readOnly: true
        - name: etc-kubernetes
          mountPath: /etc/kubernetes
          readOnly: true
        - name: usr-bin
          mountPath: /usr/local/mount-from-host/bin
          readOnly: true
      restartPolicy: Never
      volumes:
      - name: var-lib-etcd
        hostPath:
          path: "/var/lib/etcd"
      - name: var-lib-kubelet
        hostPath:
          path: "/var/lib/kubelet"
      - name: etc-systemd
        hostPath:
          path: "/etc/systemd"
      - name: etc-kubernetes
        hostPath:
          path: "/etc/kubernetes"
      - name: usr-bin
        hostPath:
          path: "/usr/bin"
```

## Security Monitoring

### Falco Security Runtime Monitoring

```yaml
# falco-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: falco
  namespace: falco-system
spec:
  selector:
    matchLabels:
      app: falco
  template:
    metadata:
      labels:
        app: falco
    spec:
      serviceAccount: falco
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
      containers:
      - name: falco
        image: falcosecurity/falco:latest
        securityContext:
          privileged: true
        args:
        - /usr/bin/falco
        - --cri=/run/containerd/containerd.sock
        - --k8s-api=https://kubernetes.default.svc.cluster.local
        - -pk
        volumeMounts:
        - mountPath: /host/var/run/docker.sock
          name: docker-socket
        - mountPath: /host/run/containerd/containerd.sock
          name: containerd-socket
        - mountPath: /host/dev
          name: dev-fs
        - mountPath: /host/proc
          name: proc-fs
          readOnly: true
        - mountPath: /host/boot
          name: boot-fs
          readOnly: true
        - mountPath: /host/lib/modules
          name: lib-modules
          readOnly: true
        - mountPath: /host/usr
          name: usr-fs
          readOnly: true
      volumes:
      - name: docker-socket
        hostPath:
          path: /var/run/docker.sock
      - name: containerd-socket
        hostPath:
          path: /run/containerd/containerd.sock
      - name: dev-fs
        hostPath:
          path: /dev
      - name: proc-fs
        hostPath:
          path: /proc
      - name: boot-fs
        hostPath:
          path: /boot
      - name: lib-modules
        hostPath:
          path: /lib/modules
      - name: usr-fs
        hostPath:
          path: /usr
```

## Compliance and Standards

### NIST Framework Implementation

```yaml
# nist-compliance-policy.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nist-security-policy
data:
  policy.yaml: |
    # NIST Cybersecurity Framework Implementation
    identify:
      - asset_management
      - business_environment
      - governance
      - risk_assessment
      - risk_management_strategy
    
    protect:
      - access_control
      - awareness_training
      - data_security
      - information_protection
      - maintenance
      - protective_technology
    
    detect:
      - anomalies_events
      - security_monitoring
      - detection_processes
    
    respond:
      - response_planning
      - communications
      - analysis
      - mitigation
      - improvements
    
    recover:
      - recovery_planning
      - improvements
      - communications
```

## Best Practices Summary

1. **Principle of Least Privilege**: Grant minimum necessary permissions
2. **Defense in Depth**: Implement security at multiple layers
3. **Regular Updates**: Keep Kubernetes and dependencies updated
4. **Audit Everything**: Enable comprehensive audit logging
5. **Network Segmentation**: Use network policies to isolate workloads
6. **Secrets Management**: Never store secrets in plain text
7. **Image Security**: Scan images and use trusted registries
8. **Runtime Security**: Monitor containers at runtime
9. **Backup and Recovery**: Implement disaster recovery procedures
10. **Compliance**: Follow industry standards and benchmarks

## Troubleshooting Common Security Issues

### Issue: Pods failing with security context constraints

```bash
# Check pod security context
kubectl describe pod <pod-name>

# Verify security context in pod spec
kubectl get pod <pod-name> -o yaml | grep -A 10 securityContext

# Check for security policy violations
kubectl get events --field-selector involvedObject.name=<pod-name>
```

### Issue: RBAC permission denied

```bash
# Check user permissions
kubectl auth can-i <verb> <resource> --as=<user>

# List role bindings
kubectl get rolebindings,clusterrolebindings -A

# Describe specific role
kubectl describe role <role-name> -n <namespace>
```

## References

- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)
- [Falco Runtime Security](https://falco.org/)
- [Aqua Security kube-bench](https://github.com/aquasecurity/kube-bench)

---

**Next**: [Authentication and Authorization](../authentication-authorization/) - Learn about identity and access management in Kubernetes.
