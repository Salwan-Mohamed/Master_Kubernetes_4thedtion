# Multi-Tenancy in Kubernetes

## Overview

Multi-tenancy in Kubernetes enables multiple teams, applications, or customers to share the same cluster while maintaining isolation and security. This section covers different multi-tenancy models, implementation strategies, and security considerations.

## Table of Contents

1. [Multi-Tenancy Models](#multi-tenancy-models)
2. [Namespace-Based Multi-Tenancy](#namespace-based-multi-tenancy)
3. [Virtual Clusters](#virtual-clusters)
4. [Node-Level Isolation](#node-level-isolation)
5. [Resource Management](#resource-management)
6. [Network Isolation](#network-isolation)
7. [Security Policies](#security-policies)
8. [Monitoring and Observability](#monitoring-and-observability)

## Multi-Tenancy Models

### Soft Multi-Tenancy (Namespace-Based)

```yaml
# namespace-tenant-setup.yaml
# Tenant namespace with security constraints
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-alpha
  labels:
    tenant: alpha
    tier: production
    security-level: standard
  annotations:
    tenant.kubernetes.io/owner: "alpha-team@company.com"
    tenant.kubernetes.io/created: "2024-01-15"
    tenant.kubernetes.io/budget-code: "ALPHA-2024"
    # Pod Security Standards
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
---
# Tenant service account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tenant-alpha-sa
  namespace: tenant-alpha
  labels:
    tenant: alpha
automountServiceAccountToken: false
---
# Tenant-specific RBAC
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: tenant-alpha
  name: tenant-alpha-role
rules:
# Full access within namespace
- apiGroups: [""]
  resources: ["*"]
  verbs: ["*"]
- apiGroups: ["apps", "extensions"]
  resources: ["*"]
  verbs: ["*"]
# Limited access to cluster resources
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["*"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: tenant-alpha-binding
  namespace: tenant-alpha
subjects:
- kind: User
  name: alpha-admin
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: alpha-developers
  apiGroup: rbac.authorization.k8s.io
- kind: ServiceAccount
  name: tenant-alpha-sa
  namespace: tenant-alpha
roleRef:
  kind: Role
  name: tenant-alpha-role
  apiGroup: rbac.authorization.k8s.io
```

### Hard Multi-Tenancy (Node Isolation)

```yaml
# node-isolated-tenant.yaml
# Dedicated node pool for tenant
apiVersion: v1
kind: Node
metadata:
  name: tenant-dedicated-node-1
  labels:
    tenant: beta
    isolation: dedicated
    node-type: compute
spec:
  taints:
  - key: tenant
    value: beta
    effect: NoSchedule
---
# Tenant workload with node affinity
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tenant-beta-app
  namespace: tenant-beta
spec:
  replicas: 3
  selector:
    matchLabels:
      app: beta-app
      tenant: beta
  template:
    metadata:
      labels:
        app: beta-app
        tenant: beta
    spec:
      # Node affinity for dedicated nodes
      nodeSelector:
        tenant: beta
      
      # Toleration for tenant taint
      tolerations:
      - key: tenant
        operator: Equal
        value: beta
        effect: NoSchedule
      
      # Anti-affinity to spread across nodes
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - beta-app
              topologyKey: kubernetes.io/hostname
      
      containers:
      - name: app
        image: tenant-beta-app:latest
        securityContext:
          runAsNonRoot: true
          runAsUser: 10000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        resources:
          limits:
            cpu: "2"
            memory: "4Gi"
          requests:
            cpu: "500m"
            memory: "1Gi"
```

## Namespace-Based Multi-Tenancy

### Tenant Onboarding Automation

```yaml
# tenant-onboarding-template.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: tenant-onboarding-template
  namespace: platform-system
data:
  tenant-template.yaml: |
    # Tenant namespace
    apiVersion: v1
    kind: Namespace
    metadata:
      name: "{{TENANT_NAME}}"
      labels:
        tenant: "{{TENANT_NAME}}"
        environment: "{{ENVIRONMENT}}"
        cost-center: "{{COST_CENTER}}"
      annotations:
        tenant.kubernetes.io/owner: "{{OWNER_EMAIL}}"
        tenant.kubernetes.io/contact: "{{CONTACT_EMAIL}}"
        pod-security.kubernetes.io/enforce: "{{SECURITY_LEVEL}}"
        pod-security.kubernetes.io/audit: "{{SECURITY_LEVEL}}"
        pod-security.kubernetes.io/warn: "{{SECURITY_LEVEL}}"
    ---
    # Resource quota
    apiVersion: v1
    kind: ResourceQuota
    metadata:
      name: "{{TENANT_NAME}}-quota"
      namespace: "{{TENANT_NAME}}"
    spec:
      hard:
        requests.cpu: "{{CPU_REQUESTS}}"
        requests.memory: "{{MEMORY_REQUESTS}}"
        limits.cpu: "{{CPU_LIMITS}}"
        limits.memory: "{{MEMORY_LIMITS}}"
        persistentvolumeclaims: "{{PVC_COUNT}}"
        requests.storage: "{{STORAGE_REQUESTS}}"
        pods: "{{POD_COUNT}}"
        services: "{{SERVICE_COUNT}}"
        secrets: "{{SECRET_COUNT}}"
        configmaps: "{{CONFIGMAP_COUNT}}"
    ---
    # Network policy
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: "{{TENANT_NAME}}-network-policy"
      namespace: "{{TENANT_NAME}}"
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      - Egress
      ingress:
      - from:
        - namespaceSelector:
            matchLabels:
              tenant: "{{TENANT_NAME}}"
      egress:
      - to: []
        ports:
        - protocol: UDP
          port: 53
      - to:
        - namespaceSelector:
            matchLabels:
              tenant: "{{TENANT_NAME}}"
---
# Tenant onboarding job
apiVersion: batch/v1
kind: Job
metadata:
  name: onboard-tenant-{{TENANT_NAME}}
  namespace: platform-system
spec:
  template:
    spec:
      restartPolicy: Never
      serviceAccountName: tenant-onboarding-sa
      containers:
      - name: onboard
        image: tenant-onboarding:latest
        command:
        - /bin/sh
        - -c
        - |
          # Replace template variables
          sed 's/{{TENANT_NAME}}/{{TENANT_NAME}}/g; \
               s/{{ENVIRONMENT}}/{{ENVIRONMENT}}/g; \
               s/{{COST_CENTER}}/{{COST_CENTER}}/g; \
               s/{{OWNER_EMAIL}}/{{OWNER_EMAIL}}/g; \
               s/{{CONTACT_EMAIL}}/{{CONTACT_EMAIL}}/g; \
               s/{{SECURITY_LEVEL}}/{{SECURITY_LEVEL}}/g; \
               s/{{CPU_REQUESTS}}/{{CPU_REQUESTS}}/g; \
               s/{{MEMORY_REQUESTS}}/{{MEMORY_REQUESTS}}/g; \
               s/{{CPU_LIMITS}}/{{CPU_LIMITS}}/g; \
               s/{{MEMORY_LIMITS}}/{{MEMORY_LIMITS}}/g; \
               s/{{PVC_COUNT}}/{{PVC_COUNT}}/g; \
               s/{{STORAGE_REQUESTS}}/{{STORAGE_REQUESTS}}/g; \
               s/{{POD_COUNT}}/{{POD_COUNT}}/g; \
               s/{{SERVICE_COUNT}}/{{SERVICE_COUNT}}/g; \
               s/{{SECRET_COUNT}}/{{SECRET_COUNT}}/g; \
               s/{{CONFIGMAP_COUNT}}/{{CONFIGMAP_COUNT}}/g' \
               /templates/tenant-template.yaml | kubectl apply -f -
          
          # Create RBAC for tenant
          kubectl create rolebinding {{TENANT_NAME}}-admin \
            --clusterrole=admin \
            --user={{OWNER_EMAIL}} \
            --namespace={{TENANT_NAME}}
          
          # Send notification
          curl -X POST $SLACK_WEBHOOK \
            -H 'Content-type: application/json' \
            --data '{"text":"Tenant {{TENANT_NAME}} has been successfully onboarded"}'
        
        env:
        - name: TENANT_NAME
          value: "new-tenant"
        - name: ENVIRONMENT
          value: "production"
        - name: COST_CENTER
          value: "CC-12345"
        - name: OWNER_EMAIL
          value: "owner@company.com"
        - name: CONTACT_EMAIL
          value: "contact@company.com"
        - name: SECURITY_LEVEL
          value: "restricted"
        - name: CPU_REQUESTS
          value: "4"
        - name: MEMORY_REQUESTS
          value: "8Gi"
        - name: CPU_LIMITS
          value: "8"
        - name: MEMORY_LIMITS
          value: "16Gi"
        - name: PVC_COUNT
          value: "10"
        - name: STORAGE_REQUESTS
          value: "100Gi"
        - name: POD_COUNT
          value: "50"
        - name: SERVICE_COUNT
          value: "20"
        - name: SECRET_COUNT
          value: "30"
        - name: CONFIGMAP_COUNT
          value: "30"
        - name: SLACK_WEBHOOK
          valueFrom:
            secretKeyRef:
              name: notification-secrets
              key: slack-webhook
        
        volumeMounts:
        - name: template-volume
          mountPath: /templates
      
      volumes:
      - name: template-volume
        configMap:
          name: tenant-onboarding-template
```

### Hierarchical Namespaces

```yaml
# hierarchical-namespaces.yaml
# Parent namespace
apiVersion: v1
kind: Namespace
metadata:
  name: company-a
  labels:
    tenant: company-a
    hierarchy-level: "1"
---
# Child namespace
apiVersion: v1
kind: Namespace
metadata:
  name: company-a-dev
  labels:
    tenant: company-a
    parent-tenant: company-a
    environment: development
    hierarchy-level: "2"
  annotations:
    hierarchy.kubernetes.io/parent: company-a
---
# Hierarchical Role (HNC - Hierarchical Namespace Controller)
apiVersion: hnc.x-k8s.io/v1alpha2
kind: HierarchyConfiguration
metadata:
  name: hierarchy
  namespace: company-a
spec:
  children:
  - company-a-dev
  - company-a-staging
  - company-a-prod
---
# Propagated network policy
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: company-a-base-policy
  namespace: company-a
  annotations:
    hnc.x-k8s.io/propagate: "true"
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  egress:
  # Allow DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow within company namespaces
  - to:
    - namespaceSelector:
        matchLabels:
          tenant: company-a
```

## Virtual Clusters

### vcluster Implementation

```yaml
# vcluster-tenant.yaml
# Virtual cluster for tenant isolation
apiVersion: v1
kind: Namespace
metadata:
  name: vcluster-tenant-gamma
  labels:
    tenant: gamma
    vcluster: "true"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vcluster-gamma
  namespace: vcluster-tenant-gamma
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vcluster-gamma
rules:
- apiGroups: [""]
  resources: ["nodes", "nodes/status"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["nodes", "nodes/status"]
  verbs: ["patch", "update"]
  resourceNames: ["vcluster-gamma"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vcluster-gamma
subjects:
- kind: ServiceAccount
  name: vcluster-gamma
  namespace: vcluster-tenant-gamma
roleRef:
  kind: ClusterRole
  name: vcluster-gamma
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: vcluster-gamma
  namespace: vcluster-tenant-gamma
spec:
  serviceName: vcluster-gamma-headless
  replicas: 1
  selector:
    matchLabels:
      app: vcluster-gamma
  template:
    metadata:
      labels:
        app: vcluster-gamma
    spec:
      serviceAccountName: vcluster-gamma
      containers:
      - name: vcluster
        image: rancher/k3s:v1.28.2-k3s1
        command:
        - /bin/k3s
        args:
        - server
        - --write-kubeconfig=/data/k3s-config/kube-config.yaml
        - --data-dir=/data
        - --disable=traefik,servicelb,metrics-server,local-storage
        - --disable-network-policy
        - --disable-agent
        - --disable-scheduler
        - --disable-controller-manager
        - --disable-etcd
        - --etcd-endpoint=http://localhost:2379
        - --service-cidr=10.96.0.0/16
        - --cluster-cidr=10.244.0.0/16
        
        securityContext:
          runAsUser: 0
          runAsGroup: 0
          privileged: true
        
        ports:
        - containerPort: 6443
          name: https
        - containerPort: 8080
          name: http
        
        volumeMounts:
        - name: data
          mountPath: /data
        
        resources:
          limits:
            cpu: "2"
            memory: "4Gi"
          requests:
            cpu: "500m"
            memory: "1Gi"
      
      - name: syncer
        image: loftsh/vcluster:0.19.0
        args:
        - --name=vcluster-gamma
        - --namespace=vcluster-tenant-gamma
        - --service-account=vcluster-gamma
        - --kube-config=/data/k3s-config/kube-config.yaml
        - --tls-san=vcluster-gamma.vcluster-tenant-gamma.svc.cluster.local
        
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        
        volumeMounts:
        - name: data
          mountPath: /data
        - name: tmp
          mountPath: /tmp
        
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "100m"
            memory: "128Mi"
      
      volumes:
      - name: tmp
        emptyDir: {}
  
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
---
apiVersion: v1
kind: Service
metadata:
  name: vcluster-gamma
  namespace: vcluster-tenant-gamma
spec:
  selector:
    app: vcluster-gamma
  ports:
  - port: 443
    targetPort: 6443
    name: https
  - port: 80
    targetPort: 8080
    name: http
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: vcluster-gamma-headless
  namespace: vcluster-tenant-gamma
spec:
  selector:
    app: vcluster-gamma
  ports:
  - port: 443
    targetPort: 6443
    name: https
  clusterIP: None
```

### Cluster API Multi-Tenancy

```yaml
# cluster-api-tenant.yaml
# Tenant-specific cluster using Cluster API
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: tenant-delta-cluster
  namespace: tenant-delta
  labels:
    tenant: delta
    cluster-type: dedicated
spec:
  clusterNetwork:
    services:
      cidrBlocks: ["10.128.0.0/12"]
    pods:
      cidrBlocks: ["192.168.0.0/16"]
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: AWSCluster
    name: tenant-delta-cluster
  controlPlaneRef:
    kind: KubeadmControlPlane
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    name: tenant-delta-cluster-control-plane
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
kind: AWSCluster
metadata:
  name: tenant-delta-cluster
  namespace: tenant-delta
spec:
  region: us-west-2
  sshKeyName: tenant-delta-key
  networkSpec:
    vpc:
      cidrBlock: "10.0.0.0/16"
      tags:
        Name: "tenant-delta-vpc"
        Tenant: "delta"
    subnets:
    - availabilityZone: us-west-2a
      cidrBlock: "10.0.1.0/24"
      isPublic: true
      tags:
        Name: "tenant-delta-public-subnet-1"
    - availabilityZone: us-west-2b
      cidrBlock: "10.0.2.0/24"
      isPublic: false
      tags:
        Name: "tenant-delta-private-subnet-1"
---
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata:
  name: tenant-delta-cluster-control-plane
  namespace: tenant-delta
spec:
  version: v1.28.0
  replicas: 3
  machineTemplate:
    infrastructureRef:
      kind: AWSMachineTemplate
      apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
      name: tenant-delta-cluster-control-plane
  kubeadmConfigSpec:
    initConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          cloud-provider: aws
    joinConfiguration:
      nodeRegistration:
        kubeletExtraArgs:
          cloud-provider: aws
```

## Node-Level Isolation

### Dedicated Node Pools

```yaml
# dedicated-node-pool.yaml
# AWS EKS Node Group for tenant isolation
apiVersion: eks.aws.crossplane.io/v1alpha1
kind: NodeGroup
metadata:
  name: tenant-epsilon-nodes
  namespace: tenant-epsilon
spec:
  forProvider:
    clusterName: main-cluster
    nodeGroupName: tenant-epsilon
    
    # Instance configuration
    instanceTypes:
    - m5.large
    - m5.xlarge
    
    # Scaling configuration
    scalingConfig:
      desiredSize: 3
      maxSize: 10
      minSize: 1
    
    # Launch template
    launchTemplate:
      version: "$Latest"
    
    # Taints for tenant isolation
    taints:
    - key: tenant
      value: epsilon
      effect: NO_SCHEDULE
    - key: dedicated
      value: "true"
      effect: NO_SCHEDULE
    
    # Labels
    labels:
      tenant: epsilon
      node-type: dedicated
      cost-center: epsilon-cc
    
    # Subnets (private subnets for security)
    subnets:
    - subnet-12345678
    - subnet-87654321
    
    # Security groups
    remoteAccess:
      ec2SshKey: tenant-epsilon-key
      sourceSecurityGroups:
      - sg-epsilon-admin
    
    # Instance profile with restricted permissions
    instanceProfile: TenantEpsilonNodeInstanceProfile
    
    # User data for additional security
    userData: |
      #!/bin/bash
      /etc/eks/bootstrap.sh main-cluster --container-runtime containerd
      
      # Additional security hardening
      echo 'net.ipv4.conf.all.log_martians = 1' >> /etc/sysctl.conf
      echo 'net.ipv4.conf.default.log_martians = 1' >> /etc/sysctl.conf
      sysctl -p
      
      # Install security monitoring agent
      curl -s https://download.falco.org/packages/rpm/falco-repo.repo | tee /etc/yum.repos.d/falco.repo
      yum install -y falco
      systemctl enable falco
      systemctl start falco
---
# Pod that uses dedicated nodes
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tenant-epsilon-app
  namespace: tenant-epsilon
spec:
  replicas: 5
  selector:
    matchLabels:
      app: epsilon-app
  template:
    metadata:
      labels:
        app: epsilon-app
        tenant: epsilon
    spec:
      # Node selection
      nodeSelector:
        tenant: epsilon
        node-type: dedicated
      
      # Tolerations for tenant taints
      tolerations:
      - key: tenant
        operator: Equal
        value: epsilon
        effect: NoSchedule
      - key: dedicated
        operator: Equal
        value: "true"
        effect: NoSchedule
      
      # Pod anti-affinity for high availability
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - epsilon-app
            topologyKey: kubernetes.io/hostname
      
      containers:
      - name: app
        image: tenant-epsilon-app:latest
        securityContext:
          runAsNonRoot: true
          runAsUser: 10000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        
        resources:
          limits:
            cpu: "1"
            memory: "2Gi"
          requests:
            cpu: "250m"
            memory: "512Mi"
        
        env:
        - name: TENANT_ID
          value: "epsilon"
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
```

## Resource Management

### Comprehensive Resource Quotas

```yaml
# tenant-resource-management.yaml
# Compute resource quota
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-zeta-compute-quota
  namespace: tenant-zeta
spec:
  hard:
    # CPU and Memory
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    
    # Storage
    requests.storage: 100Gi
    
    # Object counts
    pods: "50"
    persistentvolumeclaims: "20"
    services: "15"
    secrets: "25"
    configmaps: "25"
    replicationcontrollers: "10"
    
    # Network
    services.loadbalancers: "3"
    services.nodeports: "5"
---
# Extended resource quota
apiVersion: v1
kind: ResourceQuota
metadata:
  name: tenant-zeta-extended-quota
  namespace: tenant-zeta
spec:
  hard:
    # GPU resources
    requests.nvidia.com/gpu: "2"
    limits.nvidia.com/gpu: "4"
    
    # Custom resources
    count/deployments.apps: "10"
    count/jobs.batch: "5"
    count/ingresses.networking.k8s.io: "3"
    
    # Security-related quotas
    count/pods.spec.securityContext.runAsUser=0: "0"  # No root pods
    count/pods.spec.containers{.securityContext.privileged==true}: "0"  # No privileged containers
---
# Priority class for tenant workloads
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: tenant-zeta-priority
value: 100
globalDefault: false
description: "Priority class for tenant zeta workloads"
---
# Limit range for granular control
apiVersion: v1
kind: LimitRange
metadata:
  name: tenant-zeta-limits
  namespace: tenant-zeta
spec:
  limits:
  # Container limits
  - type: Container
    default:
      cpu: "500m"
      memory: 1Gi
      ephemeral-storage: 2Gi
    defaultRequest:
      cpu: "100m"
      memory: 256Mi
      ephemeral-storage: 512Mi
    max:
      cpu: "4"
      memory: 8Gi
      ephemeral-storage: 10Gi
    min:
      cpu: "50m"
      memory: 128Mi
      ephemeral-storage: 100Mi
  
  # Pod limits
  - type: Pod
    max:
      cpu: "8"
      memory: 16Gi
      ephemeral-storage: 20Gi
  
  # PVC limits
  - type: PersistentVolumeClaim
    max:
      storage: 50Gi
    min:
      storage: 1Gi
```

### Cost Management and Chargeback

```yaml
# cost-management.yaml
# Cost allocation labels and annotations
apiVersion: v1
kind: Namespace
metadata:
  name: tenant-cost-tracking
  labels:
    tenant: cost-tracking-example
    cost-center: "CC-56789"
    business-unit: "engineering"
    environment: "production"
    project: "web-platform"
  annotations:
    cost.kubernetes.io/allocation-method: "proportional"
    cost.kubernetes.io/budget-monthly: "5000"
    cost.kubernetes.io/alert-threshold: "80"
    cost.kubernetes.io/owner: "platform-team@company.com"
---
# Cost-aware deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cost-optimized-app
  namespace: tenant-cost-tracking
  labels:
    cost.kubernetes.io/category: "web-server"
    cost.kubernetes.io/criticality: "medium"
spec:
  replicas: 3
  selector:
    matchLabels:
      app: cost-optimized-app
  template:
    metadata:
      labels:
        app: cost-optimized-app
        cost.kubernetes.io/component: "frontend"
      annotations:
        cost.kubernetes.io/hourly-rate: "0.50"
    spec:
      # Use spot instances when possible
      nodeSelector:
        node.kubernetes.io/instance-type: "spot"
      
      containers:
      - name: app
        image: nginx:alpine
        
        # Right-sized resources
        resources:
          limits:
            cpu: "200m"
            memory: "256Mi"
          requests:
            cpu: "100m"
            memory: "128Mi"
        
        # Horizontal Pod Autoscaler target
        # Will be referenced by HPA
      
      # Use preemptible scheduling
      priorityClassName: tenant-zeta-priority
      
      # Efficient storage
      volumes:
      - name: cache
        emptyDir:
          sizeLimit: "100Mi"
---
# Horizontal Pod Autoscaler for cost efficiency
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: cost-optimized-app-hpa
  namespace: tenant-cost-tracking
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: cost-optimized-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 10
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
```

## Network Isolation

### Advanced Network Policies

```yaml
# tenant-network-isolation.yaml
# Default deny all for tenant
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-eta-default-deny
  namespace: tenant-eta
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
# Allow intra-tenant communication
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-eta-intra-communication
  namespace: tenant-eta
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tenant: eta
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          tenant: eta
---
# Allow access to shared services
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-eta-shared-services
  namespace: tenant-eta
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  # DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
  # Monitoring
  - to:
    - namespaceSelector:
        matchLabels:
          name: monitoring
    ports:
    - protocol: TCP
      port: 9090
    - protocol: TCP
      port: 3000
  # Logging
  - to:
    - namespaceSelector:
        matchLabels:
          name: logging
    ports:
    - protocol: TCP
      port: 9200
    - protocol: TCP
      port: 5601
---
# Tier-based communication (3-tier app)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-eta-web-tier
  namespace: tenant-eta
spec:
  podSelector:
    matchLabels:
      tier: web
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from ingress controller
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 8080
  egress:
  # Allow to API tier
  - to:
    - podSelector:
        matchLabels:
          tier: api
    ports:
    - protocol: TCP
      port: 8080
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-eta-api-tier
  namespace: tenant-eta
spec:
  podSelector:
    matchLabels:
      tier: api
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow from web tier
  - from:
    - podSelector:
        matchLabels:
          tier: web
    ports:
    - protocol: TCP
      port: 8080
  egress:
  # Allow to database tier
  - to:
    - podSelector:
        matchLabels:
          tier: database
    ports:
    - protocol: TCP
      port: 5432
  # Allow DNS
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-eta-database-tier
  namespace: tenant-eta
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  ingress:
  # Allow from API tier only
  - from:
    - podSelector:
        matchLabels:
          tier: api
    ports:
    - protocol: TCP
      port: 5432
```

### Service Mesh Multi-Tenancy

```yaml
# istio-multi-tenancy.yaml
# Tenant-specific Istio configuration
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
metadata:
  name: tenant-theta-istio
  namespace: tenant-theta
spec:
  # Tenant-specific mesh configuration
  meshConfig:
    defaultConfig:
      # Tenant-specific proxy configuration
      proxyMetadata:
        TENANT_ID: "theta"
      # Custom tracing configuration
      tracing:
        sampling: 100.0
        custom_tags:
          tenant_id:
            literal:
              value: "theta"
  
  values:
    global:
      # Tenant-specific mesh ID
      meshID: "tenant-theta"
      # Tenant-specific network
      network: "theta-network"
      # Multi-tenancy configuration
      proxy:
        env:
          TENANT_ID: "theta"
---
# Tenant-specific authorization policy
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: tenant-theta-policy
  namespace: tenant-theta
spec:
  # Apply to all workloads in namespace
  selector:
    matchLabels:
      tenant: theta
  rules:
  # Allow within tenant
  - from:
    - source:
        namespaces: ["tenant-theta"]
  # Allow from ingress gateway
  - from:
    - source:
        principals: ["cluster.local/ns/istio-system/sa/istio-ingressgateway-service-account"]
  # Deny everything else (implicit)
---
# Tenant-specific peer authentication
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: tenant-theta-mtls
  namespace: tenant-theta
spec:
  # Strict mTLS for all workloads
  mtls:
    mode: STRICT
---
# Tenant-specific destination rule
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: tenant-theta-default
  namespace: tenant-theta
spec:
  host: "*.tenant-theta.svc.cluster.local"
  trafficPolicy:
    # Tenant-specific load balancing
    loadBalancer:
      simple: LEAST_CONN
    # Circuit breaker
    outlierDetection:
      consecutiveErrors: 3
      interval: 30s
      baseEjectionTime: 30s
    # Retry policy
    retryPolicy:
      attempts: 3
      perTryTimeout: 10s
```

## Security Policies

### OPA Gatekeeper Multi-Tenancy

```yaml
# gatekeeper-multi-tenancy.yaml
# Constraint template for tenant isolation
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: tenantisolation
spec:
  crd:
    spec:
      names:
        kind: TenantIsolation
      validation:
        openAPIV3Schema:
          type: object
          properties:
            allowedTenants:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package tenantisolation
        
        violation[{"msg": msg}] {
          # Check if resource has tenant label
          not input.review.object.metadata.labels.tenant
          msg := "Resource must have tenant label"
        }
        
        violation[{"msg": msg}] {
          # Check if tenant is in allowed list
          tenant := input.review.object.metadata.labels.tenant
          not tenant in input.parameters.allowedTenants
          msg := sprintf("Tenant %v is not in allowed list", [tenant])
        }
        
        violation[{"msg": msg}] {
          # Check namespace matches tenant
          tenant := input.review.object.metadata.labels.tenant
          namespace := input.review.object.metadata.namespace
          not startswith(namespace, sprintf("tenant-%v", [tenant]))
          msg := sprintf("Namespace %v does not match tenant prefix for tenant %v", [namespace, tenant])
        }
---
# Constraint for tenant isolation
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: TenantIsolation
metadata:
  name: tenant-isolation-constraint
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
    - apiGroups: ["apps"]
      kinds: ["Deployment", "ReplicaSet"]
    - apiGroups: [""]
      kinds: ["Service"]
    excludedNamespaces:
    - kube-system
    - kube-public
    - gatekeeper-system
  parameters:
    allowedTenants:
    - alpha
    - beta
    - gamma
    - delta
    - epsilon
    - zeta
    - eta
    - theta
---
# Resource quota constraint template
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: tenantresourcequota
spec:
  crd:
    spec:
      names:
        kind: TenantResourceQuota
      validation:
        openAPIV3Schema:
          type: object
          properties:
            maxCpu:
              type: string
            maxMemory:
              type: string
            maxReplicas:
              type: integer
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package tenantresourcequota
        
        violation[{"msg": msg}] {
          # Check CPU limits
          input.review.object.kind == "Pod"
          container := input.review.object.spec.containers[_]
          cpu_limit := container.resources.limits.cpu
          cpu_limit_value := units.parse_bytes(cpu_limit)
          max_cpu_value := units.parse_bytes(input.parameters.maxCpu)
          cpu_limit_value > max_cpu_value
          msg := sprintf("CPU limit %v exceeds maximum %v", [cpu_limit, input.parameters.maxCpu])
        }
        
        violation[{"msg": msg}] {
          # Check memory limits
          input.review.object.kind == "Pod"
          container := input.review.object.spec.containers[_]
          memory_limit := container.resources.limits.memory
          memory_limit_value := units.parse_bytes(memory_limit)
          max_memory_value := units.parse_bytes(input.parameters.maxMemory)
          memory_limit_value > max_memory_value
          msg := sprintf("Memory limit %v exceeds maximum %v", [memory_limit, input.parameters.maxMemory])
        }
        
        violation[{"msg": msg}] {
          # Check replica count
          input.review.object.kind == "Deployment"
          replicas := input.review.object.spec.replicas
          replicas > input.parameters.maxReplicas
          msg := sprintf("Replica count %v exceeds maximum %v", [replicas, input.parameters.maxReplicas])
        }
```

## Monitoring and Observability

### Tenant-Specific Monitoring

```yaml
# tenant-monitoring.yaml
# Prometheus configuration for tenant isolation
apiVersion: v1
kind: ConfigMap
metadata:
  name: tenant-prometheus-config
  namespace: tenant-monitoring
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
      external_labels:
        cluster: 'multi-tenant-cluster'
    
    rule_files:
    - "/etc/prometheus/rules/*.yml"
    
    scrape_configs:
    # Tenant-specific service discovery
    - job_name: 'tenant-alpha'
      kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
          - tenant-alpha
      relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::[0-9]+)?;([0-9]+)
        replacement: $1:$2
        target_label: __address__
      - action: labelmap
        regex: __meta_kubernetes_pod_label_(.+)
      - source_labels: [__meta_kubernetes_namespace]
        action: replace
        target_label: kubernetes_namespace
      - source_labels: [__meta_kubernetes_pod_name]
        action: replace
        target_label: kubernetes_pod_name
      # Add tenant label
      - target_label: tenant
        replacement: alpha
    
    # Similar configurations for other tenants...
    
    alerting:
      alertmanagers:
      - static_configs:
        - targets:
          - alertmanager:9093
---
# Tenant-specific Grafana dashboard
apiVersion: v1
kind: ConfigMap
metadata:
  name: tenant-alpha-dashboard
  namespace: tenant-monitoring
  labels:
    grafana_dashboard: "1"
data:
  tenant-alpha-dashboard.json: |
    {
      "dashboard": {
        "id": null,
        "title": "Tenant Alpha Dashboard",
        "tags": ["tenant", "alpha"],
        "timezone": "browser",
        "panels": [
          {
            "id": 1,
            "title": "CPU Usage",
            "type": "graph",
            "targets": [
              {
                "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"tenant-alpha\"}[5m])) by (pod)",
                "legendFormat": "{{pod}}"
              }
            ],
            "yAxes": [
              {
                "label": "CPU Cores",
                "min": 0
              }
            ]
          },
          {
            "id": 2,
            "title": "Memory Usage",
            "type": "graph",
            "targets": [
              {
                "expr": "sum(container_memory_usage_bytes{namespace=\"tenant-alpha\"}) by (pod)",
                "legendFormat": "{{pod}}"
              }
            ],
            "yAxes": [
              {
                "label": "Bytes",
                "min": 0
              }
            ]
          },
          {
            "id": 3,
            "title": "Network I/O",
            "type": "graph",
            "targets": [
              {
                "expr": "sum(rate(container_network_receive_bytes_total{namespace=\"tenant-alpha\"}[5m])) by (pod)",
                "legendFormat": "{{pod}} - RX"
              },
              {
                "expr": "sum(rate(container_network_transmit_bytes_total{namespace=\"tenant-alpha\"}[5m])) by (pod)",
                "legendFormat": "{{pod}} - TX"
              }
            ]
          }
        ],
        "time": {
          "from": "now-1h",
          "to": "now"
        },
        "refresh": "30s"
      }
    }
---
# Tenant-specific alerting rules
apiVersion: v1
kind: ConfigMap
metadata:
  name: tenant-alpha-alerts
  namespace: tenant-monitoring
data:
  tenant-alpha-rules.yml: |
    groups:
    - name: tenant-alpha.rules
      rules:
      - alert: TenantAlphaHighCPU
        expr: sum(rate(container_cpu_usage_seconds_total{namespace="tenant-alpha"}[5m])) / sum(container_spec_cpu_quota{namespace="tenant-alpha"}/container_spec_cpu_period{namespace="tenant-alpha"}) > 0.8
        for: 5m
        labels:
          severity: warning
          tenant: alpha
        annotations:
          summary: "Tenant Alpha high CPU usage"
          description: "Tenant Alpha is using {{ $value | humanizePercentage }} of allocated CPU for more than 5 minutes."
      
      - alert: TenantAlphaHighMemory
        expr: sum(container_memory_usage_bytes{namespace="tenant-alpha"}) / sum(container_spec_memory_limit_bytes{namespace="tenant-alpha"}) > 0.8
        for: 5m
        labels:
          severity: warning
          tenant: alpha
        annotations:
          summary: "Tenant Alpha high memory usage"
          description: "Tenant Alpha is using {{ $value | humanizePercentage }} of allocated memory for more than 5 minutes."
      
      - alert: TenantAlphaPodCrashLooping
        expr: increase(kube_pod_container_status_restarts_total{namespace="tenant-alpha"}[15m]) > 5
        for: 5m
        labels:
          severity: critical
          tenant: alpha
        annotations:
          summary: "Tenant Alpha pod crash looping"
          description: "Pod {{ $labels.pod }} in tenant Alpha has restarted {{ $value }} times in the last 15 minutes."
```

### Audit Logging for Multi-Tenancy

```yaml
# multi-tenant-audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Log tenant-specific resource access
- level: Metadata
  namespaces: ["tenant-alpha", "tenant-beta", "tenant-gamma"]
  resources:
  - group: ""
    resources: ["pods", "services", "secrets", "configmaps"]
  - group: "apps"
    resources: ["deployments", "replicasets"]
  omitStages:
  - RequestReceived

# Log cross-tenant access attempts
- level: Request
  users: ["system:serviceaccount:tenant-alpha:*"]
  namespaces: ["tenant-beta", "tenant-gamma"]
  resources:
  - group: ""
    resources: ["*"]
  - group: "apps"
    resources: ["*"]

# Log cluster-level access by tenant users
- level: RequestResponse
  users: ["alpha-admin", "beta-admin", "gamma-admin"]
  resources:
  - group: ""
    resources: ["nodes", "persistentvolumes"]
  - group: "rbac.authorization.k8s.io"
    resources: ["clusterroles", "clusterrolebindings"]

# Log resource quota changes
- level: RequestResponse
  resources:
  - group: ""
    resources: ["resourcequotas", "limitranges"]
  namespaces: ["tenant-alpha", "tenant-beta", "tenant-gamma"]

# Log network policy changes
- level: RequestResponse
  resources:
  - group: "networking.k8s.io"
    resources: ["networkpolicies"]
  namespaces: ["tenant-alpha", "tenant-beta", "tenant-gamma"]
```

## Best Practices Summary

### Multi-Tenancy Security Checklist

```yaml
# multi-tenancy-checklist.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: multi-tenancy-checklist
  namespace: platform-system
data:
  checklist.md: |
    # Multi-Tenancy Security Checklist
    
    ## Namespace Isolation
    - [ ] Each tenant has dedicated namespace(s)
    - [ ] Namespaces have appropriate labels and annotations
    - [ ] Pod Security Standards are enforced
    - [ ] Resource quotas are configured
    - [ ] Limit ranges are set
    
    ## RBAC Configuration
    - [ ] Tenant-specific service accounts created
    - [ ] Least privilege RBAC roles assigned
    - [ ] No cluster-admin access for tenant users
    - [ ] Regular RBAC review scheduled
    
    ## Network Isolation
    - [ ] Default deny network policies in place
    - [ ] Tenant-to-tenant communication restricted
    - [ ] Ingress/egress rules defined
    - [ ] Service mesh policies configured (if applicable)
    
    ## Resource Management
    - [ ] CPU and memory quotas enforced
    - [ ] Storage quotas configured
    - [ ] Priority classes assigned
    - [ ] Cost allocation labels applied
    
    ## Security Policies
    - [ ] Pod security contexts enforced
    - [ ] Image policies implemented
    - [ ] Admission controllers configured
    - [ ] Security scanning enabled
    
    ## Monitoring and Logging
    - [ ] Tenant-specific metrics collected
    - [ ] Audit logging configured
    - [ ] Alerting rules defined
    - [ ] Log aggregation isolated
    
    ## Data Isolation
    - [ ] Secrets properly isolated
    - [ ] ConfigMaps scoped to tenants
    - [ ] Persistent volumes isolated
    - [ ] Backup strategies tenant-aware
    
    ## Compliance
    - [ ] Regulatory requirements met
    - [ ] Data residency enforced
    - [ ] Audit trails maintained
    - [ ] Incident response procedures defined
```

## Troubleshooting Multi-Tenancy

### Common Issues and Solutions

```bash
#!/bin/bash
# multi-tenancy-troubleshooting.sh

TENANT_NAME="$1"

if [ -z "$TENANT_NAME" ]; then
    echo "Usage: $0 <tenant-name>"
    exit 1
fi

echo "=== Multi-Tenancy Troubleshooting for Tenant: $TENANT_NAME ==="

# Check namespace existence and configuration
echo "\n=== Namespace Configuration ==="
kubectl get namespace "tenant-$TENANT_NAME" -o yaml 2>/dev/null || echo "Namespace tenant-$TENANT_NAME not found"

# Check resource quotas
echo "\n=== Resource Quotas ==="
kubectl describe resourcequota -n "tenant-$TENANT_NAME" 2>/dev/null || echo "No resource quotas found"

# Check limit ranges
echo "\n=== Limit Ranges ==="
kubectl describe limitrange -n "tenant-$TENANT_NAME" 2>/dev/null || echo "No limit ranges found"

# Check network policies
echo "\n=== Network Policies ==="
kubectl get networkpolicy -n "tenant-$TENANT_NAME" 2>/dev/null || echo "No network policies found"

# Check RBAC
echo "\n=== RBAC Configuration ==="
kubectl get rolebindings -n "tenant-$TENANT_NAME" 2>/dev/null || echo "No role bindings found"
kubectl get clusterrolebindings -o json | jq -r ".items[] | select(.subjects[]?.namespace == \"tenant-$TENANT_NAME\") | .metadata.name" 2>/dev/null

# Check pod security
echo "\n=== Pod Security ==="
kubectl get pods -n "tenant-$TENANT_NAME" -o json | jq -r '.items[] | select(.spec.securityContext.runAsUser == 0 or .spec.containers[].securityContext.runAsUser == 0) | .metadata.name' 2>/dev/null | while read pod; do
    [ -n "$pod" ] && echo "WARNING: Pod $pod running as root"
done

# Check cross-tenant communication
echo "\n=== Cross-Tenant Communication Test ==="
kubectl run test-pod --image=nicolaka/netshoot --rm -it --restart=Never -n "tenant-$TENANT_NAME" -- nc -zv kubernetes.default.svc.cluster.local 443 2>/dev/null || echo "Cannot test connectivity"

# Check resource usage
echo "\n=== Resource Usage ==="
kubectl top pods -n "tenant-$TENANT_NAME" 2>/dev/null || echo "Metrics server not available"

echo "\n=== Troubleshooting Complete ==="
```

## References

- [Kubernetes Multi-Tenancy](https://kubernetes.io/docs/concepts/security/multi-tenancy/)
- [Hierarchical Namespaces](https://github.com/kubernetes-sigs/hierarchical-namespaces)
- [vcluster](https://www.vcluster.com/)
- [Cluster API](https://cluster-api.sigs.k8s.io/)
- [OPA Gatekeeper](https://open-policy-agent.github.io/gatekeeper/)
- [Istio Multi-Tenancy](https://istio.io/latest/docs/ops/deployment/deployment-models/)

---

**Next**: [Code Examples](../Code/) - Explore practical implementation examples for all security concepts.
