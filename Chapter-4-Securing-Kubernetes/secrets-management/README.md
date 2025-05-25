# Secrets Management in Kubernetes

## Overview

Secrets management is critical for protecting sensitive data such as passwords, tokens, certificates, and API keys. This section covers Kubernetes native secrets, external secret management systems, and best practices for secure secrets handling.

## Table of Contents

1. [Kubernetes Native Secrets](#kubernetes-native-secrets)
2. [External Secret Management](#external-secret-management)
3. [HashiCorp Vault Integration](#hashicorp-vault-integration)
4. [Secret Rotation and Lifecycle](#secret-rotation-and-lifecycle)
5. [Encryption at Rest](#encryption-at-rest)
6. [Secret Scanning and Detection](#secret-scanning-and-detection)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

## Kubernetes Native Secrets

### Basic Secret Types

```yaml
# basic-secrets.yaml
# Generic Secret
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
  namespace: production
type: Opaque
data:
  # Base64 encoded values
  database-password: cGFzc3dvcmQxMjM=  # password123
  api-key: YWJjZGVmZ2hpams=              # abcdefghijk
  config.json: eyJkYiI6eyJob3N0IjoibG9jYWxob3N0In19  # {"db":{"host":"localhost"}}
stringData:
  # Plain text values (automatically base64 encoded)
  username: admin
  connection-string: "postgres://user:pass@localhost:5432/db"
---
# TLS Secret
apiVersion: v1
kind: Secret
metadata:
  name: tls-secret
  namespace: production
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTi... # Base64 encoded certificate
  tls.key: LS0tLS1CRUdJTi... # Base64 encoded private key
---
# Docker Registry Secret
apiVersion: v1
kind: Secret
metadata:
  name: registry-secret
  namespace: production
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: eyJhdXRocyI6eyJyZWdpc3RyeTo... # Base64 encoded docker config
---
# Service Account Token Secret
apiVersion: v1
kind: Secret
metadata:
  name: sa-token-secret
  namespace: production
  annotations:
    kubernetes.io/service-account.name: "my-service-account"
type: kubernetes.io/service-account-token
```

### Advanced Secret Configuration

```yaml
# advanced-secrets.yaml
# Secret with annotations and labels
apiVersion: v1
kind: Secret
metadata:
  name: advanced-secret
  namespace: production
  labels:
    app: myapp
    environment: production
    secret-type: database
  annotations:
    # Custom annotations for secret management
    secrets.example.com/rotation-schedule: "@monthly"
    secrets.example.com/owner: "database-team"
    secrets.example.com/created-by: "terraform"
    # Vault annotations
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "myapp-role"
type: Opaque
stringData:
  # Environment-specific secrets
  DATABASE_URL: "postgres://user:secure_password@db.production.svc.cluster.local:5432/myapp"
  REDIS_URL: "redis://redis.production.svc.cluster.local:6379"
  JWT_SECRET: "very-secure-jwt-secret-key"
  ENCRYPTION_KEY: "32-byte-encryption-key-here!!"
---
# Immutable Secret (Kubernetes 1.19+)
apiVersion: v1
kind: Secret
metadata:
  name: immutable-secret
  namespace: production
type: Opaque
immutable: true  # Cannot be updated once created
stringData:
  api-key: "permanent-api-key"
  license-key: "software-license-key"
```

### Using Secrets in Pods

```yaml
# secret-usage.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-secrets
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
      - name: app
        image: myapp:latest
        
        # Method 1: Environment variables from secrets
        env:
        - name: DATABASE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: database-password
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: app-secrets
              key: api-key
              optional: false  # Pod fails if secret doesn't exist
        
        # Method 2: All secret keys as environment variables
        envFrom:
        - secretRef:
            name: app-secrets
            optional: true
        
        # Method 3: Mount secrets as files
        volumeMounts:
        - name: secret-volume
          mountPath: "/etc/secrets"
          readOnly: true
        - name: tls-certs
          mountPath: "/etc/ssl/certs"
          readOnly: true
        
        # Security context
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
      
      volumes:
      # Secret as volume
      - name: secret-volume
        secret:
          secretName: app-secrets
          defaultMode: 0400  # Read-only for owner
          items:
          - key: config.json
            path: config.json
            mode: 0400
      
      # TLS certificates
      - name: tls-certs
        secret:
          secretName: tls-secret
          defaultMode: 0400
      
      # Image pull secret
      imagePullSecrets:
      - name: registry-secret
```

### Projected Volumes with Secrets

```yaml
# projected-secrets.yaml
apiVersion: v1
kind: Pod
metadata:
  name: projected-secrets-pod
  namespace: production
spec:
  containers:
  - name: app
    image: nginx:alpine
    volumeMounts:
    - name: projected-volume
      mountPath: "/etc/projected"
      readOnly: true
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
  
  volumes:
  - name: projected-volume
    projected:
      defaultMode: 0400
      sources:
      # Multiple secrets in one volume
      - secret:
          name: app-secrets
          items:
          - key: database-password
            path: db/password
      - secret:
          name: tls-secret
          items:
          - key: tls.crt
            path: certs/tls.crt
          - key: tls.key
            path: certs/tls.key
      # ConfigMap in the same volume
      - configMap:
          name: app-config
          items:
          - key: config.yaml
            path: config/app.yaml
      # Downward API
      - downwardAPI:
          items:
          - path: labels
            fieldRef:
              fieldPath: metadata.labels
      # Service account token
      - serviceAccountToken:
          path: token
          expirationSeconds: 3600
          audience: vault
```

## External Secret Management

### External Secrets Operator

```yaml
# external-secrets-operator.yaml
# Install External Secrets Operator
apiVersion: v1
kind: Namespace
metadata:
  name: external-secrets-system
---
# SecretStore for AWS Secrets Manager
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: production
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-west-2
      auth:
        # Use IAM role for service accounts (IRSA)
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
---
# ExternalSecret to sync from AWS
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets-external
  namespace: production
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: app-secrets-synced
    creationPolicy: Owner
    template:
      type: Opaque
      data:
        # Transform data during sync
        DATABASE_URL: "postgres://{{ .username }}:{{ .password }}@{{ .host }}:5432/{{ .database }}"
  data:
  - secretKey: username
    remoteRef:
      key: prod/database
      property: username
  - secretKey: password
    remoteRef:
      key: prod/database
      property: password
  - secretKey: host
    remoteRef:
      key: prod/database
      property: host
  - secretKey: database
    remoteRef:
      key: prod/database
      property: database
---
# ClusterSecretStore for global access
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-cluster-store
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets-role"
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets-system
```

### Azure Key Vault Integration

```yaml
# azure-keyvault-secrets.yaml
# SecretStore for Azure Key Vault
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: azure-keyvault
  namespace: production
spec:
  provider:
    azurekv:
      vaultUrl: "https://mykeyvault.vault.azure.net/"
      authType: ManagedIdentity
      identityId: "/subscriptions/sub-id/resourcegroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/identity"
---
# ExternalSecret for Azure Key Vault
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: azure-secrets
  namespace: production
spec:
  refreshInterval: 10m
  secretStoreRef:
    name: azure-keyvault
    kind: SecretStore
  target:
    name: azure-app-secrets
    creationPolicy: Owner
  data:
  - secretKey: api-key
    remoteRef:
      key: api-key
  - secretKey: database-connection
    remoteRef:
      key: database-connection-string
  - secretKey: certificate
    remoteRef:
      key: ssl-certificate
      property: certificate
```

### Google Secret Manager Integration

```yaml
# google-secret-manager.yaml
# SecretStore for Google Secret Manager
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: google-secret-manager
  namespace: production
spec:
  provider:
    gcpsm:
      projectId: "my-gcp-project"
      auth:
        workloadIdentity:
          clusterLocation: us-central1
          clusterName: my-cluster
          serviceAccountRef:
            name: external-secrets-sa
---
# ExternalSecret for Google Secret Manager
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: gcp-secrets
  namespace: production
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: google-secret-manager
    kind: SecretStore
  target:
    name: gcp-app-secrets
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        config.json: |
          {
            "database": {
              "host": "{{ .db_host }}",
              "password": "{{ .db_password }}"
            },
            "api": {
              "key": "{{ .api_key }}"
            }
          }
  data:
  - secretKey: db_host
    remoteRef:
      key: database-host
  - secretKey: db_password
    remoteRef:
      key: database-password
  - secretKey: api_key
    remoteRef:
      key: api-key
```

## HashiCorp Vault Integration

### Vault Agent Sidecar

```yaml
# vault-agent-sidecar.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-with-vault-agent
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: vault-app
  template:
    metadata:
      labels:
        app: vault-app
      annotations:
        # Vault Agent annotations
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "myapp-role"
        vault.hashicorp.com/agent-inject-secret-database: "database/creds/readonly"
        vault.hashicorp.com/agent-inject-template-database: |
          {{- with secret "database/creds/readonly" -}}
          export DATABASE_USERNAME="{{ .Data.username }}"
          export DATABASE_PASSWORD="{{ .Data.password }}"
          {{- end }}
        vault.hashicorp.com/agent-inject-secret-config: "secret/myapp/config"
        vault.hashicorp.com/agent-inject-template-config: |
          {{- with secret "secret/myapp/config" -}}
          {
            "api_key": "{{ .Data.data.api_key }}",
            "jwt_secret": "{{ .Data.data.jwt_secret }}"
          }
          {{- end }}
    spec:
      serviceAccountName: vault-app-sa
      containers:
      - name: app
        image: myapp:latest
        command:
        - /bin/sh
        - -c
        - |
          # Source database credentials
          source /vault/secrets/database
          # Read config file
          export API_KEY=$(jq -r '.api_key' /vault/secrets/config)
          export JWT_SECRET=$(jq -r '.jwt_secret' /vault/secrets/config)
          # Start application
          exec ./myapp
        
        securityContext:
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

### Vault CSI Driver

```yaml
# vault-csi-driver.yaml
# SecretProviderClass for Vault CSI Driver
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-secrets
  namespace: production
spec:
  provider: vault
  parameters:
    vaultAddress: "https://vault.example.com:8200"
    roleName: "myapp-role"
    objects: |
      - objectName: "api-key"
        secretPath: "secret/data/myapp"
        secretKey: "api_key"
      - objectName: "database-password"
        secretPath: "database/creds/readonly"
        secretKey: "password"
      - objectName: "tls-cert"
        secretPath: "pki/issue/myapp"
        secretKey: "certificate"
  # Sync to Kubernetes secrets
  secretObjects:
  - secretName: vault-synced-secret
    type: Opaque
    data:
    - objectName: api-key
      key: api-key
    - objectName: database-password
      key: db-password
---
# Pod using Vault CSI Driver
apiVersion: v1
kind: Pod
metadata:
  name: vault-csi-pod
  namespace: production
spec:
  serviceAccountName: vault-csi-sa
  containers:
  - name: app
    image: nginx:alpine
    volumeMounts:
    - name: vault-secrets
      mountPath: "/mnt/secrets"
      readOnly: true
    env:
    - name: API_KEY
      valueFrom:
        secretKeyRef:
          name: vault-synced-secret
          key: api-key
    securityContext:
      runAsNonRoot: true
      runAsUser: 1000
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
  
  volumes:
  - name: vault-secrets
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: vault-secrets
```

### Vault Dynamic Secrets

```yaml
# vault-dynamic-secrets.yaml
# ServiceAccount for Vault authentication
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-dynamic-sa
  namespace: production
  annotations:
    vault.hashicorp.com/role: "dynamic-secrets-role"
---
# Pod with dynamic database credentials
apiVersion: v1
kind: Pod
metadata:
  name: dynamic-secrets-pod
  namespace: production
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "dynamic-secrets-role"
    
    # Inject dynamic database credentials
    vault.hashicorp.com/agent-inject-secret-db-creds: "database/creds/myapp-role"
    vault.hashicorp.com/agent-inject-template-db-creds: |
      {{- with secret "database/creds/myapp-role" -}}
      {
        "username": "{{ .Data.username }}",
        "password": "{{ .Data.password }}",
        "lease_id": "{{ .LeaseID }}",
        "lease_duration": {{ .LeaseDuration }}
      }
      {{- end }}
    
    # Auto-renew the lease
    vault.hashicorp.com/agent-pre-populate-only: "false"
    vault.hashicorp.com/agent-cache-enable: "true"
spec:
  serviceAccountName: vault-dynamic-sa
  containers:
  - name: app
    image: postgres-client:latest
    command:
    - /bin/sh
    - -c
    - |
      # Read dynamic credentials
      DB_USERNAME=$(jq -r '.username' /vault/secrets/db-creds)
      DB_PASSWORD=$(jq -r '.password' /vault/secrets/db-creds)
      
      # Connect to database with dynamic credentials
      export PGUSER=$DB_USERNAME
      export PGPASSWORD=$DB_PASSWORD
      export PGHOST=postgres.database.svc.cluster.local
      export PGDATABASE=myapp
      
      # Application logic here
      while true; do
        psql -c "SELECT current_user, now();"
        sleep 30
      done
    
    securityContext:
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

## Secret Rotation and Lifecycle

### Automated Secret Rotation

```yaml
# secret-rotation-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: secret-rotator
  namespace: security-system
spec:
  schedule: "0 2 * * 0"  # Weekly on Sunday at 2 AM
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: secret-rotator-sa
          restartPolicy: OnFailure
          containers:
          - name: secret-rotator
            image: secret-rotator:latest
            command:
            - /bin/sh
            - -c
            - |
              echo "Starting secret rotation..."
              
              # Rotate database passwords
              NEW_PASSWORD=$(openssl rand -base64 32)
              
              # Update password in database
              PGPASSWORD=$OLD_PASSWORD psql -h postgres.db.svc.cluster.local -U myapp -c \
                "ALTER USER myapp PASSWORD '$NEW_PASSWORD';"
              
              # Update Kubernetes secret
              kubectl create secret generic app-secrets \
                --from-literal=database-password="$NEW_PASSWORD" \
                --dry-run=client -o yaml | kubectl apply -f -
              
              # Trigger rolling update of applications
              kubectl rollout restart deployment/myapp -n production
              
              # Verify deployment
              kubectl rollout status deployment/myapp -n production --timeout=300s
              
              echo "Secret rotation completed successfully"
            
            env:
            - name: OLD_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: app-secrets
                  key: database-password
            
            securityContext:
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

### Secret Lifecycle Management

```yaml
# secret-lifecycle-policy.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: secret-lifecycle-policy
  namespace: security-system
data:
  policy.yaml: |
    # Secret lifecycle management policy
    secrets:
      - name: "database-credentials"
        rotation_schedule: "@monthly"
        backup_count: 3
        notification_days: [7, 3, 1]  # Days before expiration to notify
        
      - name: "api-keys"
        rotation_schedule: "@quarterly"
        backup_count: 2
        notification_days: [14, 7, 1]
        
      - name: "tls-certificates"
        rotation_schedule: "@yearly"
        backup_count: 5
        notification_days: [30, 14, 7, 1]
    
    notifications:
      slack:
        webhook_url: "https://hooks.slack.com/services/..."
        channel: "#security-alerts"
      
      email:
        smtp_server: "smtp.example.com"
        recipients: ["security@example.com", "devops@example.com"]
---
# Secret expiration monitor
apiVersion: batch/v1
kind: CronJob
metadata:
  name: secret-expiration-monitor
  namespace: security-system
spec:
  schedule: "0 8 * * *"  # Daily at 8 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: secret-monitor-sa
          restartPolicy: OnFailure
          containers:
          - name: monitor
            image: secret-monitor:latest
            command:
            - python
            - -c
            - |
              import json
              import base64
              from datetime import datetime, timedelta
              import subprocess
              
              def check_secret_expiration(namespace, secret_name):
                  # Get secret
                  result = subprocess.run([
                      "kubectl", "get", "secret", secret_name, 
                      "-n", namespace, "-o", "json"
                  ], capture_output=True, text=True)
                  
                  if result.returncode != 0:
                      return None
                  
                  secret = json.loads(result.stdout)
                  
                  # Check creation date
                  creation_time = secret['metadata']['creationTimestamp']
                  created = datetime.strptime(creation_time, '%Y-%m-%dT%H:%M:%SZ')
                  
                  # Check if secret needs rotation (example: 90 days)
                  rotation_due = created + timedelta(days=90)
                  days_until_rotation = (rotation_due - datetime.now()).days
                  
                  return {
                      'name': secret_name,
                      'namespace': namespace,
                      'created': created,
                      'rotation_due': rotation_due,
                      'days_until_rotation': days_until_rotation
                  }
              
              # Check all secrets in production namespace
              secrets_to_check = ['app-secrets', 'tls-secret', 'registry-secret']
              
              for secret_name in secrets_to_check:
                  info = check_secret_expiration('production', secret_name)
                  if info and info['days_until_rotation'] <= 7:
                      print(f"WARNING: Secret {secret_name} expires in {info['days_until_rotation']} days")
                      # Send notification (implement notification logic)
            
            securityContext:
              runAsNonRoot: true
              runAsUser: 1000
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                - ALL
```

## Encryption at Rest

### etcd Encryption Configuration

```yaml
# encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  - configmaps
  providers:
  # Multiple encryption providers for rotation
  - aescbc:
      keys:
      - name: key1
        secret: <32-byte-base64-encoded-key>
  - aescbc:
      keys:
      - name: key2
        secret: <32-byte-base64-encoded-key>
  # Identity provider for reading old unencrypted data
  - identity: {}
---
# Key rotation script
apiVersion: v1
kind: ConfigMap
metadata:
  name: encryption-key-rotation
  namespace: kube-system
data:
  rotate-keys.sh: |
    #!/bin/bash
    set -e
    
    echo "Starting encryption key rotation..."
    
    # Generate new encryption key
    NEW_KEY=$(head -c 32 /dev/urandom | base64)
    
    # Update encryption config with new key as primary
    cat > /tmp/new-encryption-config.yaml <<EOF
    apiVersion: apiserver.config.k8s.io/v1
    kind: EncryptionConfiguration
    resources:
    - resources:
      - secrets
      - configmaps
      providers:
      - aescbc:
          keys:
          - name: key-$(date +%Y%m%d)
            secret: $NEW_KEY
      - aescbc:
          keys:
          - name: key1
            secret: <old-key>
      - identity: {}
    EOF
    
    # Update API server configuration
    sudo cp /tmp/new-encryption-config.yaml /etc/kubernetes/encryption-config.yaml
    
    # Restart API server
    sudo systemctl restart kubelet
    
    # Wait for API server to be ready
    until kubectl get nodes; do sleep 5; done
    
    # Re-encrypt all secrets with new key
    kubectl get secrets --all-namespaces -o json | kubectl replace -f -
    
    echo "Encryption key rotation completed"
```

### Sealed Secrets

```yaml
# sealed-secrets.yaml
# SealedSecret (encrypted at rest in Git)
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: sealed-app-secrets
  namespace: production
spec:
  encryptedData:
    # These are encrypted with the cluster's public key
    database-password: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEQAx...
    api-key: AgAKAoiQm7ob2Z/M7WvRunBhup4d8b1W...
  template:
    metadata:
      name: app-secrets
      namespace: production
    type: Opaque
---
# Create sealed secret from command line:
# echo -n 'mypassword' | kubectl create secret generic mysecret --dry-run=client --from-file=password=/dev/stdin -o yaml | kubeseal -o yaml > mysealedsecret.yaml
```

## Secret Scanning and Detection

### GitLeaks Integration

```yaml
# gitleaks-scan.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: gitleaks-scan
  namespace: security
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: gitleaks
        image: zricethezav/gitleaks:latest
        command:
        - gitleaks
        args:
        - detect
        - --source
        - /repo
        - --config
        - /config/gitleaks.toml
        - --report-format
        - json
        - --report-path
        - /reports/gitleaks-report.json
        - --exit-code
        - "1"  # Fail if secrets found
        
        volumeMounts:
        - name: repo-volume
          mountPath: /repo
        - name: config-volume
          mountPath: /config
        - name: reports-volume
          mountPath: /reports
        
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
      
      volumes:
      - name: repo-volume
        gitRepo:
          repository: "https://github.com/myorg/myapp.git"
      - name: config-volume
        configMap:
          name: gitleaks-config
      - name: reports-volume
        emptyDir: {}
---
# GitLeaks configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: gitleaks-config
  namespace: security
data:
  gitleaks.toml: |
    [extend]
    useDefault = true
    
    [[rules]]
    description = "AWS Access Key ID"
    regex = '''AKIA[0-9A-Z]{16}'''
    tags = ["aws", "credentials"]
    
    [[rules]]
    description = "AWS Secret Access Key"
    regex = '''[A-Za-z0-9/+=]{40}'''
    tags = ["aws", "credentials"]
    
    [[rules]]
    description = "Kubernetes Service Account Token"
    regex = '''eyJ[A-Za-z0-9_/+-]*\.eyJ[A-Za-z0-9_/+-]*\.[A-Za-z0-9_/+-]*'''
    tags = ["kubernetes", "token"]
    
    [allowlist]
    description = "Allowlist"
    files = ['''^.*_test\.go$''', '''^.*test.*\.yaml$''']
    paths = ['''^tests/''']
```

### TruffleHog Secret Detection

```yaml
# trufflehog-scan.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: trufflehog-scan
  namespace: security
spec:
  schedule: "0 3 * * *"  # Daily at 3 AM
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: trufflehog
            image: trufflesecurity/trufflehog:latest
            command:
            - trufflehog
            args:
            - kubernetes
            - --namespace=production
            - --json
            - --only-verified
            
            env:
            - name: KUBECONFIG
              value: /etc/kubeconfig/config
            
            volumeMounts:
            - name: kubeconfig
              mountPath: /etc/kubeconfig
              readOnly: true
            
            securityContext:
              runAsNonRoot: true
              runAsUser: 1000
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                - ALL
          
          volumes:
          - name: kubeconfig
            secret:
              secretName: scanner-kubeconfig
          
          serviceAccountName: secret-scanner-sa
```

## Best Practices

### Secret Security Checklist

```yaml
# secure-secret-example.yaml
# This example demonstrates all secret security best practices
apiVersion: v1
kind: Secret
metadata:
  name: best-practices-secret
  namespace: production
  labels:
    # ✓ Use descriptive labels
    app: myapp
    environment: production
    secret-type: database
    managed-by: external-secrets-operator
  annotations:
    # ✓ Document secret purpose and ownership
    description: "Database credentials for myapp production environment"
    owner: "database-team@example.com"
    created-by: "terraform"
    rotation-schedule: "monthly"
    last-rotated: "2024-01-15"
    # ✓ Link to external secret management
    external-secrets.io/source: "vault:secret/myapp/database"
type: Opaque
# ✓ Use stringData instead of data when possible (more readable)
stringData:
  # ✓ Use descriptive key names
  database-username: "myapp_user"
  database-password: "secure-generated-password-32-chars"
  # ✓ Store connection strings as complete URIs
  database-url: "postgres://myapp_user:secure-generated-password-32-chars@postgres.db.svc.cluster.local:5432/myapp?sslmode=require"
# ✓ Make secret immutable if it shouldn't change
immutable: false  # Set to true for permanent secrets
---
# Usage example with all security best practices
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: secure-app
  template:
    metadata:
      labels:
        app: secure-app
    spec:
      # ✓ Use dedicated service account
      serviceAccountName: secure-app-sa
      # ✓ Don't mount SA token unless needed
      automountServiceAccountToken: false
      
      containers:
      - name: app
        image: myapp:latest@sha256:abc123...  # ✓ Use image digest
        
        # ✓ Use environment variables for secrets when possible
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: best-practices-secret
              key: database-url
              optional: false  # ✓ Fail if secret missing
        
        # ✓ Mount secrets as files for sensitive data
        volumeMounts:
        - name: db-certs
          mountPath: "/etc/ssl/db"
          readOnly: true  # ✓ Always read-only
        
        # ✓ Use security context
        securityContext:
          runAsNonRoot: true
          runAsUser: 1000
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
            - ALL
        
        # ✓ Set resource limits
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "100m"
            memory: "128Mi"
      
      volumes:
      - name: db-certs
        secret:
          secretName: database-tls-certs
          defaultMode: 0400  # ✓ Restrictive file permissions
          items:
          - key: ca.crt
            path: ca.crt
            mode: 0400
          - key: client.crt
            path: client.crt
            mode: 0400
          - key: client.key
            path: client.key
            mode: 0400
      
      # ✓ Use image pull secrets for private registries
      imagePullSecrets:
      - name: private-registry-secret
```

### Secret Management Policy

```yaml
# secret-management-policy.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: secret-management-policy
  namespace: security-system
data:
  policy.md: |
    # Secret Management Policy
    
    ## General Rules
    1. **Never commit secrets to version control**
    2. **Use external secret management when possible**
    3. **Rotate secrets regularly**
    4. **Use least privilege access**
    5. **Monitor secret access and usage**
    
    ## Secret Types and Handling
    
    ### Database Credentials
    - **Rotation**: Monthly
    - **Storage**: Vault or managed database service
    - **Access**: Application service accounts only
    - **Monitoring**: Log all access attempts
    
    ### API Keys
    - **Rotation**: Quarterly or when compromised
    - **Storage**: External secret manager
    - **Access**: Specific applications only
    - **Monitoring**: Rate limiting and access logs
    
    ### TLS Certificates
    - **Rotation**: Before expiration (90 days)
    - **Storage**: cert-manager or external CA
    - **Access**: Ingress controllers and applications
    - **Monitoring**: Certificate expiration alerts
    
    ### Service Account Tokens
    - **Rotation**: Automatic (short-lived tokens)
    - **Storage**: Kubernetes native
    - **Access**: Pod service accounts only
    - **Monitoring**: Token usage and anomalies
    
    ## Compliance Requirements
    - All secrets must be encrypted at rest
    - Access must be logged and auditable
    - Secrets must have expiration dates
    - Regular secret scanning required
    - Incident response plan for compromised secrets
```

## Troubleshooting

### Secret Debugging Commands

```bash
#!/bin/bash
# secret-debug.sh

SECRET_NAME="$1"
NAMESPACE="${2:-default}"

echo "=== Secret Debug Information ==="
echo "Secret: $SECRET_NAME"
echo "Namespace: $NAMESPACE"
echo

# Check if secret exists
echo "=== Secret Existence ==="
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "✓ Secret exists"
else
    echo "✗ Secret does not exist"
    exit 1
fi

# Get secret metadata
echo "\n=== Secret Metadata ==="
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o yaml | yq '.metadata'

# Check secret type
echo "\n=== Secret Type ==="
SECRET_TYPE=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.type}')
echo "Type: $SECRET_TYPE"

# List secret keys (without values)
echo "\n=== Secret Keys ==="
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys[]'

# Check secret usage
echo "\n=== Pods Using This Secret ==="
kubectl get pods -n "$NAMESPACE" -o json | jq -r "
  .items[] |
  select(
    .spec.volumes[]?.secret?.secretName == \"$SECRET_NAME\" or
    .spec.containers[].env[]?.valueFrom?.secretKeyRef?.name == \"$SECRET_NAME\" or
    .spec.containers[].envFrom[]?.secretRef?.name == \"$SECRET_NAME\"
  ) |
  .metadata.name
"

# Check RBAC permissions
echo "\n=== RBAC Permissions ==="
kubectl auth can-i get secrets --as=system:serviceaccount:$NAMESPACE:default -n "$NAMESPACE"
kubectl auth can-i list secrets --as=system:serviceaccount:$NAMESPACE:default -n "$NAMESPACE"

# Check for external secret management
echo "\n=== External Secret Management ==="
if kubectl get externalsecrets -n "$NAMESPACE" 2>/dev/null | grep -q "$SECRET_NAME"; then
    echo "✓ Managed by External Secrets Operator"
    kubectl get externalsecrets -n "$NAMESPACE" -o json | jq -r ".items[] | select(.spec.target.name == \"$SECRET_NAME\") | .metadata.name"
else
    echo "○ Not managed by External Secrets Operator"
fi

# Check secret events
echo "\n=== Recent Events ==="
kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$SECRET_NAME" --sort-by='.lastTimestamp' | tail -5

echo "\n=== Debug Complete ==="
```

### Common Secret Issues

```yaml
# secret-troubleshooting.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: secret-troubleshooting-guide
  namespace: security-system
data:
  troubleshooting.md: |
    # Secret Troubleshooting Guide
    
    ## Issue: Pod fails to start with secret mount error
    **Symptoms**: Pod stuck in `ContainerCreating` state
    **Cause**: Secret doesn't exist or has wrong name
    **Solution**:
    ```bash
    kubectl describe pod <pod-name>
    kubectl get secrets -n <namespace>
    kubectl create secret generic <secret-name> --from-literal=key=value
    ```
    
    ## Issue: Environment variable from secret is empty
    **Symptoms**: Application can't access secret value
    **Cause**: Wrong secret key name or base64 encoding issue
    **Solution**:
    ```bash
    kubectl get secret <secret-name> -o yaml
    echo '<base64-value>' | base64 -d
    ```
    
    ## Issue: Permission denied accessing secret
    **Symptoms**: 403 Forbidden when accessing secret
    **Cause**: Insufficient RBAC permissions
    **Solution**:
    ```bash
    kubectl auth can-i get secrets --as=system:serviceaccount:<namespace>:<sa-name>
    kubectl create rolebinding secret-reader --role=secret-reader --serviceaccount=<namespace>:<sa-name>
    ```
    
    ## Issue: External secret not syncing
    **Symptoms**: ExternalSecret shows error status
    **Cause**: Authentication or configuration issue
    **Solution**:
    ```bash
    kubectl describe externalsecret <external-secret-name>
    kubectl logs -n external-secrets-system deployment/external-secrets
    ```
    
    ## Issue: Vault agent injection not working
    **Symptoms**: Vault secrets not appearing in pod
    **Cause**: Annotations missing or Vault authentication failed
    **Solution**:
    ```bash
    kubectl describe pod <pod-name> | grep vault
    kubectl logs <pod-name> -c vault-agent
    ```
```

## References

- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [External Secrets Operator](https://external-secrets.io/)
- [HashiCorp Vault](https://www.vaultproject.io/docs/platform/k8s)
- [Sealed Secrets](https://sealed-secrets.netlify.app/)
- [Secret Management Best Practices](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
- [Encryption at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)

---

**Next**: [Multi-Tenancy](../multi-tenancy/) - Learn about implementing secure multi-tenant Kubernetes clusters.
