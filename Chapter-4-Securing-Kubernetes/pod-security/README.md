# Pod and Container Security

## Overview

Pod and container security focuses on protecting individual workloads through security contexts, runtime security, image security, and resource constraints. This section covers comprehensive security measures for containers and pods.

## Table of Contents

1. [Security Contexts](#security-contexts)
2. [Pod Security Standards](#pod-security-standards)
3. [Container Runtime Security](#container-runtime-security)
4. [Image Security](#image-security)
5. [Resource Limits and Security](#resource-limits-and-security)
6. [AppArmor and SELinux](#apparmor-and-selinux)
7. [Seccomp Profiles](#seccomp-profiles)
8. [Runtime Security Monitoring](#runtime-security-monitoring)

## Security Contexts

### Pod-Level Security Context

```yaml
# secure-pod-context.yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: production
spec:
  # Pod-level security context
  securityContext:
    # Run as non-root user
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    
    # Filesystem group for volumes
    fsGroup: 2000
    fsGroupChangePolicy: "OnRootMismatch"
    
    # Supplemental groups
    supplementalGroups: [3000, 4000]
    
    # SELinux options
    seLinuxOptions:
      level: "s0:c123,c456"
      role: "object_r"
      type: "container_t"
      user: "system_u"
    
    # Seccomp profile
    seccompProfile:
      type: RuntimeDefault
    
    # Sysctl settings
    sysctls:
    - name: "net.core.somaxconn"
      value: "1024"
  
  containers:
  - name: app
    image: nginx:alpine
    
    # Container-level security context
    securityContext:
      # Privilege settings
      allowPrivilegeEscalation: false
      privileged: false
      
      # User settings (inherit from pod if not specified)
      runAsNonRoot: true
      runAsUser: 1001  # Override pod setting
      runAsGroup: 1001
      
      # Read-only root filesystem
      readOnlyRootFilesystem: true
      
      # Capabilities
      capabilities:
        drop:
        - ALL
        add:
        - NET_BIND_SERVICE  # Only if needed for port < 1024
      
      # Seccomp profile (can override pod setting)
      seccompProfile:
        type: RuntimeDefault
    
    # Volume mounts for writable directories
    volumeMounts:
    - name: tmp-volume
      mountPath: /tmp
    - name: var-cache
      mountPath: /var/cache/nginx
    - name: var-run
      mountPath: /var/run
    
    ports:
    - containerPort: 8080  # Non-privileged port
    
    # Resource limits
    resources:
      limits:
        cpu: "500m"
        memory: "512Mi"
        ephemeral-storage: "1Gi"
      requests:
        cpu: "100m"
        memory: "128Mi"
        ephemeral-storage: "100Mi"
  
  # Volumes for writable directories
  volumes:
  - name: tmp-volume
    emptyDir:
      sizeLimit: "100Mi"
  - name: var-cache
    emptyDir:
      sizeLimit: "50Mi"
  - name: var-run
    emptyDir:
      sizeLimit: "10Mi"
  
  # Additional pod security settings
  hostNetwork: false
  hostPID: false
  hostIPC: false
  
  # DNS policy
  dnsPolicy: ClusterFirst
  
  # Service account
  serviceAccountName: secure-app-sa
  automountServiceAccountToken: false  # Mount only if needed
```

### Security Context Constraints (OpenShift)

```yaml
# security-context-constraint.yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: restricted-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegedContainer: false
allowedCapabilities: null
defaultAddCapabilities: null
fsGroup:
  type: MustRunAs
  ranges:
  - min: 1000
    max: 65535
readOnlyRootFilesystem: true
requiredDropCapabilities:
- ALL
runAsUser:
  type: MustRunAsNonRoot
seLinuxContext:
  type: MustRunAs
supplementalGroups:
  type: MustRunAs
  ranges:
  - min: 1000
    max: 65535
volumes:
- configMap
- downwardAPI
- emptyDir
- persistentVolumeClaim
- projected
- secret
users:
- system:serviceaccount:production:secure-app-sa
```

## Pod Security Standards

### Baseline Pod Security

```yaml
# baseline-security-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: baseline-app
  namespace: development
spec:
  replicas: 3
  selector:
    matchLabels:
      app: baseline-app
  template:
    metadata:
      labels:
        app: baseline-app
      annotations:
        # Pod security annotations
        seccomp.security.alpha.kubernetes.io/pod: runtime/default
    spec:
      securityContext:
        # Baseline requirements
        runAsNonRoot: true
        runAsUser: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
      
      containers:
      - name: app
        image: nginx:alpine
        securityContext:
          # Baseline security context
          allowPrivilegeEscalation: false
          runAsNonRoot: true
          runAsUser: 10001
          capabilities:
            drop:
            - ALL
          seccompProfile:
            type: RuntimeDefault
        
        ports:
        - containerPort: 8080
        
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: var-cache
          mountPath: /var/cache/nginx
      
      volumes:
      - name: tmp
        emptyDir: {}
      - name: var-cache
        emptyDir: {}
      
      # Baseline pod security
      hostNetwork: false
      hostPID: false
      hostIPC: false
```

### Restricted Pod Security

```yaml
# restricted-security-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: restricted-app
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: restricted-app
  template:
    metadata:
      labels:
        app: restricted-app
    spec:
      securityContext:
        # Restricted requirements - most secure
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault
        supplementalGroups: []
      
      containers:
      - name: app
        image: nginx:alpine
        securityContext:
          # Restricted security context
          allowPrivilegeEscalation: false
          privileged: false
          runAsNonRoot: true
          runAsUser: 10001
          runAsGroup: 10001
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
          seccompProfile:
            type: RuntimeDefault
        
        ports:
        - containerPort: 8080
        
        # All mount points must be explicitly defined
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: var-cache
          mountPath: /var/cache/nginx
        - name: var-run
          mountPath: /var/run
        
        # Strict resource limits
        resources:
          limits:
            cpu: "200m"
            memory: "256Mi"
            ephemeral-storage: "512Mi"
          requests:
            cpu: "100m"
            memory: "128Mi"
            ephemeral-storage: "100Mi"
      
      volumes:
      - name: tmp
        emptyDir:
          sizeLimit: "100Mi"
      - name: var-cache
        emptyDir:
          sizeLimit: "50Mi"
      - name: var-run
        emptyDir:
          sizeLimit: "10Mi"
      
      # Restricted pod settings
      hostNetwork: false
      hostPID: false
      hostIPC: false
      serviceAccountName: restricted-app-sa
      automountServiceAccountToken: false
```

### Pod Security Policy (Deprecated but still relevant)

```yaml
# pod-security-policy.yaml
apiVersion: policy/v1beta1
kind: PodSecurityPolicy
metadata:
  name: restricted-psp
spec:
  # Privilege settings
  privileged: false
  allowPrivilegeEscalation: false
  
  # User settings
  runAsUser:
    rule: 'MustRunAsNonRoot'
  runAsGroup:
    rule: 'MustRunAs'
    ranges:
    - min: 1000
      max: 65535
  
  # Filesystem settings
  fsGroup:
    rule: 'MustRunAs'
    ranges:
    - min: 1000
      max: 65535
  readOnlyRootFilesystem: true
  
  # Volume types
  volumes:
  - 'configMap'
  - 'emptyDir'
  - 'projected'
  - 'secret'
  - 'downwardAPI'
  - 'persistentVolumeClaim'
  
  # Network settings
  hostNetwork: false
  hostIPC: false
  hostPID: false
  hostPorts:
  - min: 0
    max: 0  # No host ports allowed
  
  # Capabilities
  defaultAllowPrivilegeEscalation: false
  allowedCapabilities: []
  requiredDropCapabilities:
  - ALL
  
  # SELinux
  seLinux:
    rule: 'RunAsAny'
  
  # Seccomp
  seccomp:
    defaultProfileName: 'runtime/default'
  
  # AppArmor
  annotations:
    apparmor.security.beta.kubernetes.io/allowedProfileNames: 'runtime/default'
    apparmor.security.beta.kubernetes.io/defaultProfileName: 'runtime/default'
```

## Container Runtime Security

### gVisor Sandboxed Runtime

```yaml
# gvisor-runtime-class.yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
overhead:
  podFixed:
    memory: "20Mi"
    cpu: "10m"
scheduling:
  nodeClassification:
    tolerations:
    - effect: NoSchedule
      key: runtime
      value: gvisor
---
# Pod using gVisor
apiVersion: v1
kind: Pod
metadata:
  name: sandboxed-pod
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
    volumeMounts:
    - name: tmp
      mountPath: /tmp
  volumes:
  - name: tmp
    emptyDir: {}
```

### Kata Containers Runtime

```yaml
# kata-runtime-class.yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-containers
handler: kata-runtime
overhead:
  podFixed:
    memory: "160Mi"
    cpu: "250m"
scheduling:
  nodeClassification:
    tolerations:
    - effect: NoSchedule
      key: runtime
      value: kata
---
# High-security workload using Kata
apiVersion: apps/v1
kind: Deployment
metadata:
  name: high-security-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: high-security-app
  template:
    metadata:
      labels:
        app: high-security-app
    spec:
      runtimeClassName: kata-containers
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
      - name: app
        image: my-secure-app:latest
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        resources:
          limits:
            memory: "512Mi"
            cpu: "500m"
          requests:
            memory: "256Mi"
            cpu: "100m"
```

## Image Security

### Image Scanning with Trivy

```yaml
# image-scanning-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: image-security-scan
  namespace: security
spec:
  template:
    spec:
      containers:
      - name: trivy-scanner
        image: aquasec/trivy:latest
        command:
        - trivy
        args:
        - image
        - --format
        - json
        - --output
        - /reports/scan-result.json
        - --severity
        - HIGH,CRITICAL
        - --exit-code
        - "1"  # Fail job if vulnerabilities found
        - nginx:alpine
        volumeMounts:
        - name: reports
          mountPath: /reports
        env:
        - name: TRIVY_DB_REPOSITORY
          value: "ghcr.io/aquasecurity/trivy-db"
      volumes:
      - name: reports
        emptyDir: {}
      restartPolicy: Never
  backoffLimit: 3
```

### Image Policy with OPA Gatekeeper

```yaml
# image-policy-constraint.yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: allowedimages
spec:
  crd:
    spec:
      names:
        kind: AllowedImages
      validation:
        openAPIV3Schema:
          type: object
          properties:
            allowedImages:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package allowedimages
        
        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not image_allowed(container.image)
          msg := sprintf("Image %v is not allowed", [container.image])
        }
        
        image_allowed(image) {
          allowed_image := input.parameters.allowedImages[_]
          startswith(image, allowed_image)
        }
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: AllowedImages
metadata:
  name: allowed-images-constraint
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
  parameters:
    allowedImages:
    - "gcr.io/my-project/"
    - "docker.io/library/"
    - "quay.io/myorg/"
```

### Signed Image Verification

```yaml
# cosign-image-verification.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionWebhook
metadata:
  name: cosign-webhook
webhooks:
- name: cosign.sigstore.dev
  clientConfig:
    service:
      name: cosign-webhook
      namespace: cosign-system
      path: "/validate"
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["apps"]
    apiVersions: ["v1"]
    resources: ["deployments", "replicasets"]
  failurePolicy: Fail
  admissionReviewVersions: ["v1", "v1beta1"]
---
# ConfigMap for Cosign policies
apiVersion: v1
kind: ConfigMap
metadata:
  name: cosign-policies
  namespace: cosign-system
data:
  policy.yaml: |
    apiVersion: v1alpha1
    kind: ClusterImagePolicy
    metadata:
      name: signed-images-policy
    spec:
      images:
      - glob: "gcr.io/my-project/**"
      authorities:
      - keyless:
          url: https://fulcio.sigstore.dev
          identities:
          - issuer: https://accounts.google.com
            subject: "build@mycompany.com"
```

## Resource Limits and Security

### Comprehensive Resource Management

```yaml
# resource-quota-security.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: security-resource-quota
  namespace: production
spec:
  hard:
    # Compute resources
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    
    # Storage resources
    requests.storage: 100Gi
    persistentvolumeclaims: "10"
    
    # Object counts
    pods: "20"
    services: "10"
    secrets: "20"
    configmaps: "20"
    
    # Security-related limits
    count/pods.spec.containers{.securityContext.privileged==true}: "0"
    count/pods.spec.containers{.securityContext.allowPrivilegeEscalation==true}: "0"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: security-limit-range
  namespace: production
spec:
  limits:
  # Container limits
  - type: Container
    default:
      cpu: "500m"
      memory: "512Mi"
      ephemeral-storage: "1Gi"
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
      ephemeral-storage: "100Mi"
    max:
      cpu: "2"
      memory: "4Gi"
      ephemeral-storage: "10Gi"
    min:
      cpu: "50m"
      memory: "64Mi"
      ephemeral-storage: "10Mi"
  
  # Pod limits
  - type: Pod
    max:
      cpu: "4"
      memory: "8Gi"
      ephemeral-storage: "20Gi"
  
  # PVC limits
  - type: PersistentVolumeClaim
    max:
      storage: 50Gi
    min:
      storage: 1Gi
```

### Memory and CPU Security

```yaml
# secure-resource-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-secure-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: resource-secure-app
  template:
    metadata:
      labels:
        app: resource-secure-app
    spec:
      containers:
      - name: app
        image: nginx:alpine
        
        # Strict resource limits prevent resource exhaustion attacks
        resources:
          limits:
            cpu: "500m"  # Hard limit
            memory: "512Mi"  # Hard limit
            ephemeral-storage: "1Gi"  # Hard limit
          requests:
            cpu: "100m"  # Guaranteed resources
            memory: "128Mi"  # Guaranteed resources
            ephemeral-storage: "100Mi"  # Guaranteed resources
        
        # Liveness and readiness probes prevent resource hogging
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2
        
        # Security context
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
          capabilities:
            drop:
            - ALL
      
      # Pod-level resource controls
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
```

## AppArmor and SELinux

### AppArmor Profile

```yaml
# apparmor-profile.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: apparmor-profile
  namespace: security
data:
  nginx-profile: |
    #include <tunables/global>
    
    profile nginx-restricted flags=(attach_disconnected,mediate_deleted) {
      #include <abstractions/base>
      #include <abstractions/nameservice>
      #include <abstractions/nginx>
      
      # Allow nginx binary
      /usr/sbin/nginx mr,
      
      # Allow configuration files
      /etc/nginx/** r,
      
      # Allow log files
      /var/log/nginx/** w,
      
      # Allow temporary files
      /tmp/** rw,
      /var/cache/nginx/** rw,
      
      # Network access
      network inet tcp,
      
      # Deny dangerous capabilities
      deny capability sys_admin,
      deny capability sys_module,
      deny capability sys_rawio,
      
      # Deny access to sensitive files
      deny /etc/shadow r,
      deny /etc/passwd w,
      deny /proc/sys/** w,
      
      # Allow only specific system calls
      deny ptrace,
      deny mount,
      deny umount,
    }
---
# Pod with AppArmor profile
apiVersion: v1
kind: Pod
metadata:
  name: apparmor-secured-pod
  annotations:
    container.apparmor.security.beta.kubernetes.io/nginx: localhost/nginx-restricted
spec:
  containers:
  - name: nginx
    image: nginx:alpine
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: var-cache
      mountPath: /var/cache/nginx
  volumes:
  - name: tmp
    emptyDir: {}
  - name: var-cache
    emptyDir: {}
```

### SELinux Configuration

```yaml
# selinux-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: selinux-secured-pod
spec:
  securityContext:
    # SELinux context for the pod
    seLinuxOptions:
      level: "s0:c123,c456"  # Multi-Category Security (MCS)
      role: "object_r"
      type: "container_t"
      user: "system_u"
    runAsNonRoot: true
    runAsUser: 1000
  
  containers:
  - name: app
    image: nginx:alpine
    securityContext:
      # Container-specific SELinux context
      seLinuxOptions:
        level: "s0:c123,c456"
        role: "object_r"
        type: "container_t"
        user: "system_u"
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
    
    volumeMounts:
    - name: app-data
      mountPath: /data
  
  volumes:
  - name: app-data
    persistentVolumeClaim:
      claimName: app-data-pvc
---
# SELinux-aware PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data-pvc
  annotations:
    # SELinux context for the volume
    volume.beta.kubernetes.io/mount-options: "context=\"system_u:object_r:container_file_t:s0:c123,c456\""
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

## Seccomp Profiles

### Custom Seccomp Profile

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32"
  ],
  "syscalls": [
    {
      "names": [
        "accept",
        "accept4",
        "access",
        "bind",
        "brk",
        "chdir",
        "clone",
        "close",
        "connect",
        "dup",
        "dup2",
        "epoll_create",
        "epoll_ctl",
        "epoll_wait",
        "execve",
        "exit",
        "exit_group",
        "fcntl",
        "fork",
        "fstat",
        "futex",
        "getcwd",
        "getpid",
        "gettid",
        "listen",
        "lseek",
        "mmap",
        "munmap",
        "open",
        "openat",
        "read",
        "recvfrom",
        "sendto",
        "socket",
        "stat",
        "write"
      ],
      "action": "SCMP_ACT_ALLOW"
    },
    {
      "names": [
        "ptrace",
        "personality",
        "modify_ldt"
      ],
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
```

```yaml
# seccomp-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: seccomp-pod
spec:
  securityContext:
    # Pod-level seccomp profile
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/nginx-seccomp.json
  
  containers:
  - name: nginx
    image: nginx:alpine
    securityContext:
      # Container-level seccomp profile (overrides pod-level)
      seccompProfile:
        type: RuntimeDefault  # Use container runtime's default profile
      runAsNonRoot: true
      runAsUser: 1000
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
    
    volumeMounts:
    - name: tmp
      mountPath: /tmp
  
  volumes:
  - name: tmp
    emptyDir: {}
```

## Runtime Security Monitoring

### Falco Rules for Container Security

```yaml
# falco-rules.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: falco-rules
  namespace: falco-system
data:
  custom_rules.yaml: |
    - rule: Detect Privilege Escalation
      desc: Detect attempts to escalate privileges
      condition: >
        spawned_process and
        (proc.name in (sudo, su)) and
        container
      output: >
        Privilege escalation attempt detected
        (user=%user.name command=%proc.cmdline container=%container.name
        image=%container.image)
      priority: WARNING
      tags: [container, privilege_escalation]
    
    - rule: Detect Sensitive File Access
      desc: Detect access to sensitive files
      condition: >
        open_read and
        fd.name in (/etc/passwd, /etc/shadow, /etc/sudoers) and
        container
      output: >
        Sensitive file accessed
        (user=%user.name file=%fd.name container=%container.name
        image=%container.image)
      priority: ERROR
      tags: [container, file_access]
    
    - rule: Detect Network Tool Usage
      desc: Detect usage of network tools in containers
      condition: >
        spawned_process and
        proc.name in (nc, ncat, netcat, nmap, socat, tcpdump, tshark, wireshark) and
        container
      output: >
        Network tool usage detected
        (user=%user.name command=%proc.cmdline container=%container.name
        image=%container.image)
      priority: WARNING
      tags: [container, network]
    
    - rule: Detect Container Drift
      desc: Detect when new executable is created in container
      condition: >
        spawned_process and
        container and
        proc.is_exe_upper_layer=true
      output: >
        New executable created in container
        (user=%user.name command=%proc.cmdline container=%container.name
        image=%container.image file=%proc.exe)
      priority: ERROR
      tags: [container, drift]
```

### Runtime Security Monitoring with Sysdig

```yaml
# sysdig-secure-agent.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: sysdig-agent
  namespace: sysdig-agent
spec:
  selector:
    matchLabels:
      app: sysdig-agent
  template:
    metadata:
      labels:
        app: sysdig-agent
    spec:
      hostNetwork: true
      hostPID: true
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
      containers:
      - name: sysdig-agent
        image: sysdig/agent:latest
        securityContext:
          privileged: true
        env:
        - name: ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: sysdig-agent
              key: access-key
        - name: TAGS
          value: "role:security,env:production"
        - name: ADDITIONAL_CONF
          value: |
            security:
              enabled: true
            runtime_security:
              enabled: true
            compliance:
              enabled: true
        volumeMounts:
        - mountPath: /host/var/run/docker.sock
          name: docker-sock
        - mountPath: /host/dev
          name: dev-vol
        - mountPath: /host/proc
          name: proc-vol
          readOnly: true
        - mountPath: /host/boot
          name: boot-vol
          readOnly: true
        - mountPath: /host/lib/modules
          name: modules-vol
          readOnly: true
        - mountPath: /host/usr
          name: usr-vol
          readOnly: true
      volumes:
      - name: docker-sock
        hostPath:
          path: /var/run/docker.sock
      - name: dev-vol
        hostPath:
          path: /dev
      - name: proc-vol
        hostPath:
          path: /proc
      - name: boot-vol
        hostPath:
          path: /boot
      - name: modules-vol
        hostPath:
          path: /lib/modules
      - name: usr-vol
        hostPath:
          path: /usr
```

## Best Practices Summary

### Security Checklist

```yaml
# security-checklist-pod.yaml
# This pod demonstrates all security best practices
apiVersion: v1
kind: Pod
metadata:
  name: security-best-practices
  namespace: production
  labels:
    app: secure-app
    version: v1.0.0
  annotations:
    # AppArmor profile
    container.apparmor.security.beta.kubernetes.io/app: localhost/secure-app-profile
    # Seccomp profile
    seccomp.security.alpha.kubernetes.io/pod: localhost/secure-app-seccomp.json
spec:
  # Pod-level security context
  securityContext:
    runAsNonRoot: true           # ✓ Never run as root
    runAsUser: 10001            # ✓ Specific non-root user
    runAsGroup: 10001           # ✓ Specific group
    fsGroup: 10001              # ✓ Filesystem group
    seccompProfile:             # ✓ Seccomp profile
      type: RuntimeDefault
    seLinuxOptions:             # ✓ SELinux (if available)
      level: "s0:c123,c456"
  
  # Service account
  serviceAccountName: secure-app-sa          # ✓ Dedicated service account
  automountServiceAccountToken: false        # ✓ Don't mount token unless needed
  
  # Host settings
  hostNetwork: false          # ✓ Don't use host network
  hostPID: false             # ✓ Don't use host PID
  hostIPC: false             # ✓ Don't use host IPC
  
  containers:
  - name: app
    image: my-secure-app:v1.0.0@sha256:abc123...  # ✓ Pinned image with digest
    
    # Container security context
    securityContext:
      allowPrivilegeEscalation: false    # ✓ No privilege escalation
      privileged: false                  # ✓ Not privileged
      runAsNonRoot: true                 # ✓ Non-root user
      runAsUser: 10001                   # ✓ Specific user
      readOnlyRootFilesystem: true       # ✓ Read-only root filesystem
      capabilities:                      # ✓ Drop all capabilities
        drop:
        - ALL
      seccompProfile:                    # ✓ Seccomp profile
        type: RuntimeDefault
    
    # Resource limits
    resources:
      limits:
        cpu: "500m"                      # ✓ CPU limit
        memory: "512Mi"                  # ✓ Memory limit
        ephemeral-storage: "1Gi"         # ✓ Storage limit
      requests:
        cpu: "100m"                      # ✓ CPU request
        memory: "128Mi"                  # ✓ Memory request
        ephemeral-storage: "100Mi"       # ✓ Storage request
    
    # Health checks
    livenessProbe:                       # ✓ Liveness probe
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
    
    readinessProbe:                      # ✓ Readiness probe
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
    
    # Environment variables from secrets
    env:
    - name: DATABASE_PASSWORD            # ✓ Secrets from environment
      valueFrom:
        secretKeyRef:
          name: app-secrets
          key: db-password
    
    # Volume mounts for writable directories
    volumeMounts:
    - name: tmp-volume                   # ✓ Writable /tmp
      mountPath: /tmp
    - name: app-cache                    # ✓ Application cache
      mountPath: /app/cache
    - name: app-logs                     # ✓ Application logs
      mountPath: /app/logs
  
  # Volumes
  volumes:
  - name: tmp-volume
    emptyDir:
      sizeLimit: "100Mi"
  - name: app-cache
    emptyDir:
      sizeLimit: "200Mi"
  - name: app-logs
    emptyDir:
      sizeLimit: "500Mi"
```

## Troubleshooting Security Issues

### Security Context Debugging

```bash
#!/bin/bash
# security-debug.sh

POD_NAME="$1"
NAMESPACE="${2:-default}"

echo "=== Security Context Analysis for Pod: $POD_NAME ==="

# Get pod security context
echo "\n=== Pod Security Context ==="
kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.securityContext}' | jq .

# Get container security contexts
echo "\n=== Container Security Contexts ==="
kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.spec.containers[*].securityContext}' | jq .

# Check runtime information
echo "\n=== Runtime Information ==="
kubectl exec $POD_NAME -n $NAMESPACE -- id
kubectl exec $POD_NAME -n $NAMESPACE -- cat /proc/self/status | grep -E '(Uid|Gid|Groups)'

# Check capabilities
echo "\n=== Capabilities ==="
kubectl exec $POD_NAME -n $NAMESPACE -- cat /proc/self/status | grep Cap

# Check seccomp status
echo "\n=== Seccomp Status ==="
kubectl exec $POD_NAME -n $NAMESPACE -- cat /proc/self/status | grep Seccomp

# Check SELinux context (if available)
echo "\n=== SELinux Context ==="
kubectl exec $POD_NAME -n $NAMESPACE -- cat /proc/self/attr/current 2>/dev/null || echo "SELinux not available"

# Check AppArmor profile (if available)
echo "\n=== AppArmor Profile ==="
kubectl exec $POD_NAME -n $NAMESPACE -- cat /proc/self/attr/apparmor/current 2>/dev/null || echo "AppArmor not available"

# Check filesystem permissions
echo "\n=== Filesystem Permissions ==="
kubectl exec $POD_NAME -n $NAMESPACE -- ls -la / | head -10

echo "\n=== Security Analysis Complete ==="
```

## References

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Security Contexts](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [AppArmor in Kubernetes](https://kubernetes.io/docs/tutorials/security/apparmor/)
- [Seccomp in Kubernetes](https://kubernetes.io/docs/concepts/security/seccomp/)
- [Container Runtime Security](https://kubernetes.io/docs/concepts/security/runtime-security/)
- [Falco Runtime Security](https://falco.org/)

---

**Next**: [Secrets Management](../secrets-management/) - Learn about secure secrets management with Kubernetes and external systems.
