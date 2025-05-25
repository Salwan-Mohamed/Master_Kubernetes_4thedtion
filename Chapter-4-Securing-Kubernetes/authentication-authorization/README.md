# Authentication and Authorization in Kubernetes

## Overview

Kubernetes provides a sophisticated authentication and authorization system that controls who can access the cluster and what actions they can perform. This section covers the various authentication methods, authorization modes, and admission controllers.

## Table of Contents

1. [Authentication Methods](#authentication-methods)
2. [Authorization Modes](#authorization-modes)
3. [Role-Based Access Control (RBAC)](#role-based-access-control-rbac)
4. [Service Accounts](#service-accounts)
5. [Admission Controllers](#admission-controllers)
6. [OpenID Connect Integration](#openid-connect-integration)
7. [Certificate Management](#certificate-management)
8. [Best Practices](#best-practices)

## Authentication Methods

Kubernetes supports multiple authentication strategies:

### 1. X.509 Client Certificates

The most common method for cluster administrators:

```bash
# Generate client certificate
openssl genrsa -out john.key 2048
openssl req -new -key john.key -out john.csr -subj "/CN=john/O=developers"

# Sign the certificate with cluster CA
openssl x509 -req -in john.csr -CA /etc/kubernetes/pki/ca.crt \
  -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out john.crt -days 365

# Create kubeconfig
kubectl config set-credentials john \
  --client-certificate=john.crt \
  --client-key=john.key

kubectl config set-context john-context \
  --cluster=kubernetes \
  --user=john
```

### 2. Service Account Tokens

For pods and services:

```yaml
# service-account-example.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-service-account
  namespace: default
automountServiceAccountToken: true
---
apiVersion: v1
kind: Secret
metadata:
  name: my-service-account-token
  namespace: default
  annotations:
    kubernetes.io/service-account.name: my-service-account
type: kubernetes.io/service-account-token
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-with-sa
spec:
  serviceAccountName: my-service-account
  containers:
  - name: app
    image: nginx
    env:
    - name: TOKEN
      valueFrom:
        secretKeyRef:
          name: my-service-account-token
          key: token
```

### 3. OpenID Connect (OIDC)

For integration with external identity providers:

```yaml
# kube-apiserver configuration for OIDC
apiVersion: v1
kind: Pod
metadata:
  name: kube-apiserver
spec:
  containers:
  - command:
    - kube-apiserver
    # OIDC configuration
    - --oidc-issuer-url=https://accounts.google.com
    - --oidc-client-id=<your-client-id>
    - --oidc-username-claim=email
    - --oidc-groups-claim=groups
    - --oidc-ca-file=/etc/kubernetes/pki/oidc-ca.crt
```

### 4. Webhook Token Authentication

```yaml
# webhook-config.yaml
apiVersion: v1
kind: Config
clusters:
- name: webhook
  cluster:
    server: https://webhook.example.com/authenticate
    certificate-authority: /etc/kubernetes/pki/webhook-ca.crt
users:
- name: webhook
  user:
    client-certificate: /etc/kubernetes/pki/webhook.crt
    client-key: /etc/kubernetes/pki/webhook.key
contexts:
- context:
    cluster: webhook
    user: webhook
  name: webhook
current-context: webhook
```

## Authorization Modes

Kubernetes supports several authorization modes:

### 1. Role-Based Access Control (RBAC)

The recommended authorization mode:

```yaml
# rbac-example.yaml
# Define a Role
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: development
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
---
# Bind the Role to a User
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: development
subjects:
- kind: User
  name: john
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### 2. Attribute-Based Access Control (ABAC)

```json
{
  "apiVersion": "abac.authorization.kubernetes.io/v1beta1",
  "kind": "Policy",
  "spec": {
    "user": "alice",
    "namespace": "projectCaribou",
    "resource": "pods",
    "apiGroup": ""
  }
}
```

### 3. Node Authorization

Specially designed for kubelet:

```yaml
# API server configuration
apiVersion: v1
kind: Pod
metadata:
  name: kube-apiserver
spec:
  containers:
  - command:
    - kube-apiserver
    - --authorization-mode=Node,RBAC
```

## Role-Based Access Control (RBAC)

### Cluster-Level Permissions

```yaml
# cluster-roles.yaml
# Cluster Admin Role
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-admin-custom
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
- nonResourceURLs: ["*"]
  verbs: ["*"]
---
# Cluster Read-Only Role
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-reader
rules:
- apiGroups: [""]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["extensions"]
  resources: ["*"]
  verbs: ["get", "list", "watch"]
---
# Bind to User
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-reader-binding
subjects:
- kind: User
  name: readonly-user
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-reader
  apiGroup: rbac.authorization.k8s.io
```

### Namespace-Level Permissions

```yaml
# namespace-roles.yaml
# Developer Role
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: development
  name: developer
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["pods/exec", "pods/log"]
  verbs: ["create", "get"]
---
# QA Role (Read-Only in Production)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: production
  name: qa-readonly
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
---
# Role Binding for Developer Team
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: development
subjects:
- kind: User
  name: alice
  apiGroup: rbac.authorization.k8s.io
- kind: User
  name: bob
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: developers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

### Custom Resource Permissions

```yaml
# custom-resource-rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: custom-resource-manager
rules:
# Standard resources
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
# Custom resources
- apiGroups: ["example.com"]
  resources: ["customresources"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
# Custom resource status
- apiGroups: ["example.com"]
  resources: ["customresources/status"]
  verbs: ["get", "update", "patch"]
# Finalizers
- apiGroups: ["example.com"]
  resources: ["customresources/finalizers"]
  verbs: ["update"]
```

## Service Accounts

### Advanced Service Account Configuration

```yaml
# advanced-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-service-account
  namespace: production
  annotations:
    # AWS IAM role annotation for IRSA
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/MyServiceAccountRole
    # Azure managed identity
    azure.workload.identity/client-id: "your-client-id"
automountServiceAccountToken: true
imagePullSecrets:
- name: private-registry-secret
secrets:
- name: app-service-account-token
---
# Custom Service Account Token
apiVersion: v1
kind: Secret
metadata:
  name: app-service-account-token
  namespace: production
  annotations:
    kubernetes.io/service-account.name: app-service-account
type: kubernetes.io/service-account-token
---
# Service Account with Custom Role
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: production
  name: app-role
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["app-config"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-role-binding
  namespace: production
subjects:
- kind: ServiceAccount
  name: app-service-account
  namespace: production
roleRef:
  kind: Role
  name: app-role
  apiGroup: rbac.authorization.k8s.io
```

### Token Projection and Security

```yaml
# token-projection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: app-with-projected-token
spec:
  serviceAccountName: app-service-account
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - mountPath: /var/run/secrets/tokens
      name: vault-token
      readOnly: true
    env:
    - name: VAULT_TOKEN_PATH
      value: /var/run/secrets/tokens/vault-token
  volumes:
  - name: vault-token
    projected:
      sources:
      - serviceAccountToken:
          path: vault-token
          expirationSeconds: 3600
          audience: vault
```

## Admission Controllers

### Pod Security Admission

```yaml
# pod-security-policy.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: secure-namespace
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted  
    pod-security.kubernetes.io/warn: restricted
---
# Example pod that complies with restricted policy
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: secure-namespace
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx:alpine
    securityContext:
      allowPrivilegeEscalation: false
      runAsNonRoot: true
      runAsUser: 1000
      runAsGroup: 1000
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
      seccompProfile:
        type: RuntimeDefault
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: var-cache
      mountPath: /var/cache/nginx
    - name: var-run
      mountPath: /var/run
  volumes:
  - name: tmp
    emptyDir: {}
  - name: var-cache
    emptyDir: {}
  - name: var-run
    emptyDir: {}
```

### Custom Admission Controller

```yaml
# validating-admission-webhook.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionWebhook
metadata:
  name: security-validator
webhooks:
- name: pod-security.example.com
  clientConfig:
    service:
      name: security-webhook
      namespace: kube-system
      path: "/validate"
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  admissionReviewVersions: ["v1", "v1beta1"]
  sideEffects: None
  failurePolicy: Fail
```

## OpenID Connect Integration

### Dex OIDC Provider Setup

```yaml
# dex-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: dex-config
  namespace: auth-system
data:
  config.yaml: |
    issuer: https://dex.example.com
    
    storage:
      type: kubernetes
      config:
        inCluster: true
    
    web:
      http: 0.0.0.0:5556
    
    connectors:
    - type: ldap
      id: ldap
      name: LDAP
      config:
        host: ldap.example.com:636
        insecureNoSSL: false
        bindDN: cn=admin,dc=example,dc=com
        bindPW: password
        usernamePrompt: Email Address
        userSearch:
          baseDN: ou=People,dc=example,dc=com
          filter: "(objectClass=person)"
          username: mail
          idAttr: DN
          emailAttr: mail
          nameAttr: cn
        groupSearch:
          baseDN: ou=Groups,dc=example,dc=com
          filter: "(objectClass=groupOfNames)"
          userAttr: DN
          groupAttr: member
          nameAttr: cn
    
    oauth2:
      skipApprovalScreen: true
    
    staticClients:
    - id: kubernetes
      redirectURIs:
      - 'urn:ietf:wg:oauth:2.0:oob'
      name: 'Kubernetes'
      secret: kubernetes-client-secret
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dex
  namespace: auth-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dex
  template:
    metadata:
      labels:
        app: dex
    spec:
      containers:
      - image: dexidp/dex:v2.35.0
        name: dex
        command: ["dex", "serve", "/etc/dex/cfg/config.yaml"]
        ports:
        - name: http
          containerPort: 5556
        volumeMounts:
        - name: config
          mountPath: /etc/dex/cfg
      volumes:
      - name: config
        configMap:
          name: dex-config
```

### OIDC Client Configuration

```bash
#!/bin/bash
# oidc-login.sh

# Get OIDC token
OIDC_ISSUER="https://dex.example.com"
CLIENT_ID="kubernetes"
CLIENT_SECRET="kubernetes-client-secret"

# Use kubectl oidc-login plugin or manual token retrieval
kubectl oidc-login setup \
  --oidc-issuer-url=$OIDC_ISSUER \
  --oidc-client-id=$CLIENT_ID \
  --oidc-client-secret=$CLIENT_SECRET

# Configure kubeconfig
kubectl config set-credentials oidc-user \
  --auth-provider=oidc \
  --auth-provider-arg=idp-issuer-url=$OIDC_ISSUER \
  --auth-provider-arg=client-id=$CLIENT_ID \
  --auth-provider-arg=client-secret=$CLIENT_SECRET
```

## Certificate Management

### Certificate Rotation

```bash
#!/bin/bash
# cert-rotation.sh

echo "Starting certificate rotation..."

# Backup existing certificates
sudo mkdir -p /etc/kubernetes/pki/backup
sudo cp -r /etc/kubernetes/pki/*.crt /etc/kubernetes/pki/backup/
sudo cp -r /etc/kubernetes/pki/*.key /etc/kubernetes/pki/backup/

# Generate new CA certificate (if needed)
# WARNING: This will require updating all client certificates
# openssl genrsa -out /etc/kubernetes/pki/ca.key 2048
# openssl req -new -x509 -days 365 -key /etc/kubernetes/pki/ca.key \
#   -out /etc/kubernetes/pki/ca.crt -subj "/CN=kubernetes-ca"

# Rotate API server certificate
sudo kubeadm certs renew apiserver

# Rotate API server kubelet client certificate
sudo kubeadm certs renew apiserver-kubelet-client

# Rotate controller manager certificate
sudo kubeadm certs renew controller-manager.conf

# Rotate scheduler certificate
sudo kubeadm certs renew scheduler.conf

# Rotate admin certificate
sudo kubeadm certs renew admin.conf

# Restart control plane components
sudo systemctl restart kubelet

echo "Certificate rotation completed. Please update kubeconfig files."
```

### Certificate Signing Request (CSR) Approval

```yaml
# csr-example.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: john-csr
spec:
  request: LS0tLS1CRUdJTi... # base64 encoded CSR
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
```

```bash
# Approve CSR
kubectl certificate approve john-csr

# Get signed certificate
kubectl get csr john-csr -o jsonpath='{.status.certificate}' | base64 -d > john.crt
```

## Best Practices

### 1. Principle of Least Privilege

```yaml
# minimal-permissions.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: myapp
  name: minimal-app-role
rules:
# Only allow specific operations on specific resources
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["app-config"]
  verbs: ["get"]
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames: ["app-secret"]
  verbs: ["get"]
# No wildcard permissions
# No cluster-level permissions unless absolutely necessary
```

### 2. Regular Access Review

```bash
#!/bin/bash
# access-review.sh

echo "=== RBAC Access Review ==="
echo "Date: $(date)"

echo "\n=== ClusterRoleBindings ==="
kubectl get clusterrolebindings -o custom-columns=NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name

echo "\n=== RoleBindings by Namespace ==="
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  echo "\nNamespace: $ns"
  kubectl get rolebindings -n $ns -o custom-columns=NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name 2>/dev/null
done

echo "\n=== Service Accounts with Tokens ==="
kubectl get serviceaccounts -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,SECRETS:.secrets[*].name

echo "\n=== Unused Service Accounts ==="
# Find service accounts not used by any pods
for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
  echo "\nNamespace: $ns"
  kubectl get pods -n $ns -o jsonpath='{.items[*].spec.serviceAccountName}' | tr ' ' '\n' | sort | uniq > /tmp/used-sa-$ns
  kubectl get serviceaccounts -n $ns -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | sort > /tmp/all-sa-$ns
  comm -23 /tmp/all-sa-$ns /tmp/used-sa-$ns
done

rm -f /tmp/used-sa-* /tmp/all-sa-*
```

### 3. Authentication Audit

```yaml
# auth-audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Log all authentication attempts
- level: Metadata
  omitStages:
  - RequestReceived
  resources:
  - group: ""
    resources: ["users", "groups", "serviceaccounts"]
  
# Log RBAC changes
- level: RequestResponse
  resources:
  - group: "rbac.authorization.k8s.io"
    resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
  
# Log failed authentications
- level: Request
  users: ["system:anonymous"]
  
# Log privilege escalation attempts
- level: RequestResponse
  resources:
  - group: ""
    resources: ["pods/exec", "pods/attach", "pods/portforward"]
```

## Troubleshooting Common Issues

### Debug RBAC Permissions

```bash
# Check if user can perform action
kubectl auth can-i create pods --as=john --namespace=development

# List all permissions for a user
kubectl auth can-i --list --as=john --namespace=development

# Debug service account permissions
kubectl auth can-i create deployments --as=system:serviceaccount:default:my-service-account

# Check role bindings for a user
kubectl get rolebindings,clusterrolebindings -A -o wide | grep john
```

### Certificate Issues

```bash
# Check certificate expiration
kubeadm certs check-expiration

# Verify certificate details
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -text -noout

# Test API server connectivity
curl -k https://kubernetes-api-server:6443/version \
  --cert /etc/kubernetes/pki/apiserver-kubelet-client.crt \
  --key /etc/kubernetes/pki/apiserver-kubelet-client.key
```

## Security Testing

### RBAC Testing Script

```bash
#!/bin/bash
# rbac-test.sh

TEST_USER="test-user"
TEST_NAMESPACE="test-namespace"

echo "Testing RBAC for user: $TEST_USER in namespace: $TEST_NAMESPACE"

# Test basic operations
echo "\n=== Testing Pod Operations ==="
kubectl auth can-i create pods --as=$TEST_USER -n $TEST_NAMESPACE
kubectl auth can-i get pods --as=$TEST_USER -n $TEST_NAMESPACE
kubectl auth can-i delete pods --as=$TEST_USER -n $TEST_NAMESPACE

echo "\n=== Testing Secret Operations ==="
kubectl auth can-i create secrets --as=$TEST_USER -n $TEST_NAMESPACE
kubectl auth can-i get secrets --as=$TEST_USER -n $TEST_NAMESPACE

echo "\n=== Testing Cluster-Level Operations ==="
kubectl auth can-i create clusterroles --as=$TEST_USER
kubectl auth can-i get nodes --as=$TEST_USER

echo "\n=== Full Permission List ==="
kubectl auth can-i --list --as=$TEST_USER -n $TEST_NAMESPACE
```

## References

- [Kubernetes Authentication](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)
- [Kubernetes Authorization](https://kubernetes.io/docs/reference/access-authn-authz/authorization/)
- [RBAC Documentation](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Service Accounts](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [Admission Controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
- [Certificate Management](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)

---

**Next**: [Network Security](../network-security/) - Learn about securing network communication in Kubernetes.
