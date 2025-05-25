# Network Security in Kubernetes

## Overview

Network security is crucial for protecting Kubernetes clusters from unauthorized access and data breaches. This section covers network policies, service mesh security, ingress security, and network segmentation strategies.

## Table of Contents

1. [Network Policies](#network-policies)
2. [Service Mesh Security](#service-mesh-security)
3. [Ingress Security](#ingress-security)
4. [Network Segmentation](#network-segmentation)
5. [Container Network Interface (CNI) Security](#container-network-interface-cni-security)
6. [TLS and Certificate Management](#tls-and-certificate-management)
7. [Network Monitoring and Logging](#network-monitoring-and-logging)
8. [Best Practices](#best-practices)

## Network Policies

Network policies provide layer 3/4 traffic filtering and segmentation.

### Default Deny Policy

Start with a default deny policy for maximum security:

```yaml
# default-deny-all.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Allow Specific Communication

```yaml
# allow-web-to-db.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-db
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 5432
---
# Allow web pods to access external APIs
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-egress
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
  egress:
  # Allow DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow HTTPS to external APIs
  - to: []
    ports:
    - protocol: TCP
      port: 443
  # Allow access to database in same namespace
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
```

### Cross-Namespace Communication

```yaml
# cross-namespace-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-frontend-namespace
  namespace: backend
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: frontend
      podSelector:
        matchLabels:
          app: web
    ports:
    - protocol: TCP
      port: 8080
```

### Advanced Network Policy with IP Blocks

```yaml
# ip-block-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-access
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Allow traffic from load balancer subnet
  - from:
    - ipBlock:
        cidr: 10.0.1.0/24
    ports:
    - protocol: TCP
      port: 80
  egress:
  # Allow access to specific external service
  - to:
    - ipBlock:
        cidr: 203.0.113.0/24
        except:
        - 203.0.113.1/32  # Exclude specific IP
    ports:
    - protocol: TCP
      port: 443
  # Allow DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
```

### Monitoring Network Policies

```yaml
# network-policy-test-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: network-test-pod
  namespace: production
  labels:
    app: test
spec:
  containers:
  - name: network-test
    image: nicolaka/netshoot
    command: ["sleep", "3600"]
    securityContext:
      capabilities:
        add: ["NET_ADMIN"]
---
# Test connectivity
# kubectl exec -it network-test-pod -n production -- nmap -p 5432 database-service
# kubectl exec -it network-test-pod -n production -- curl -I http://web-service
```

## Service Mesh Security

### Istio Security Configuration

```yaml
# istio-security.yaml
# Strict mTLS for entire mesh
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
---
# Service-specific mTLS
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: web-service-mtls
  namespace: production
spec:
  selector:
    matchLabels:
      app: web
  mtls:
    mode: STRICT
  portLevelMtls:
    8080:
      mode: PERMISSIVE  # Allow both mTLS and plain text for migration
---
# Authorization Policy
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: web-authz
  namespace: production
spec:
  selector:
    matchLabels:
      app: web
  rules:
  - from:
    - source:
        principals: ["cluster.local/ns/frontend/sa/web-service"]
  - to:
    - operation:
        methods: ["GET", "POST"]
        paths: ["/api/*"]
  - when:
    - key: source.ip
      values: ["10.0.0.0/8"]
```

### JWT Authentication with Istio

```yaml
# jwt-authentication.yaml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: jwt-auth
  namespace: production
spec:
  selector:
    matchLabels:
      app: web
  jwtRules:
  - issuer: "https://auth.example.com"
    jwksUri: "https://auth.example.com/.well-known/jwks.json"
    audiences:
    - "api.example.com"
    forwardOriginalToken: true
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: jwt-authz
  namespace: production
spec:
  selector:
    matchLabels:
      app: web
  rules:
  - from:
    - source:
        requestPrincipals: ["https://auth.example.com/user@example.com"]
  - when:
    - key: request.auth.claims[role]
      values: ["admin", "user"]
```

### Linkerd Security

```yaml
# linkerd-security.yaml
# Automatic mTLS with Linkerd
apiVersion: v1
kind: Service
metadata:
  name: web-service
  namespace: production
  annotations:
    linkerd.io/inject: enabled
spec:
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: production
  annotations:
    linkerd.io/inject: enabled
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
      annotations:
        linkerd.io/inject: enabled
    spec:
      containers:
      - name: web
        image: nginx:alpine
        ports:
        - containerPort: 8080
```

### Service Mesh Authorization Policies

```yaml
# linkerd-authorization.yaml
apiVersion: policy.linkerd.io/v1beta1
kind: Server
metadata:
  name: web-server
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: web
  port: 8080
  proxyProtocol: HTTP/2
---
apiVersion: policy.linkerd.io/v1beta1
kind: ServerAuthorization
metadata:
  name: web-server-authz
  namespace: production
spec:
  server:
    name: web-server
  requiredRoutes:
  - pathRegex: "/api/.*"
    method: GET
  client:
    meshTLS:
      serviceAccounts:
      - name: frontend-sa
        namespace: frontend
```

## Ingress Security

### NGINX Ingress with TLS

```yaml
# secure-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-app-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-protocols: "TLSv1.2 TLSv1.3"
    nginx.ingress.kubernetes.io/ssl-ciphers: "ECDHE-RSA-AES128-GCM-SHA256,ECDHE-RSA-AES256-GCM-SHA384"
    nginx.ingress.kubernetes.io/auth-type: basic
    nginx.ingress.kubernetes.io/auth-secret: basic-auth-secret
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'
    # Rate limiting
    nginx.ingress.kubernetes.io/rate-limit-requests-per-second: "10"
    nginx.ingress.kubernetes.io/rate-limit-burst-multiplier: "5"
    # WAF
    nginx.ingress.kubernetes.io/enable-modsecurity: "true"
    nginx.ingress.kubernetes.io/modsecurity-snippet: |
      SecRuleEngine On
      SecRule ARGS "@detectSQLi" "id:1001,phase:2,block,msg:'SQL Injection Attack Detected'"
spec:
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls-secret
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
---
# TLS Secret
apiVersion: v1
kind: Secret
metadata:
  name: app-tls-secret
  namespace: production
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTi... # base64 encoded certificate
  tls.key: LS0tLS1CRUdJTi... # base64 encoded private key
---
# Basic Auth Secret
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth-secret
  namespace: production
type: Opaque
data:
  auth: YWRtaW46JGFwcjEkSDY... # htpasswd generated hash
```

### Cert-Manager for Automatic TLS

```yaml
# cert-manager-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
    - dns01:
        cloudflare:
          email: admin@example.com
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
---
# Automatic TLS Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: auto-tls-ingress
  namespace: production
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  tls:
  - hosts:
    - app.example.com
    secretName: app-auto-tls
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### OAuth2 Proxy Integration

```yaml
# oauth2-proxy.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oauth2-proxy
  namespace: auth-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: oauth2-proxy
  template:
    metadata:
      labels:
        app: oauth2-proxy
    spec:
      containers:
      - name: oauth2-proxy
        image: quay.io/oauth2-proxy/oauth2-proxy:latest
        args:
        - --provider=oidc
        - --oidc-issuer-url=https://accounts.google.com
        - --upstream=http://web-service.production.svc.cluster.local
        - --http-address=0.0.0.0:4180
        - --email-domain=example.com
        - --cookie-secure=true
        - --cookie-httponly=true
        - --cookie-samesite=lax
        env:
        - name: OAUTH2_PROXY_CLIENT_ID
          valueFrom:
            secretKeyRef:
              name: oauth2-proxy-secret
              key: client-id
        - name: OAUTH2_PROXY_CLIENT_SECRET
          valueFrom:
            secretKeyRef:
              name: oauth2-proxy-secret
              key: client-secret
        - name: OAUTH2_PROXY_COOKIE_SECRET
          valueFrom:
            secretKeyRef:
              name: oauth2-proxy-secret
              key: cookie-secret
        ports:
        - containerPort: 4180
          name: http
```

## Network Segmentation

### Multi-Tier Application Segmentation

```yaml
# multi-tier-segmentation.yaml
# Frontend tier - only accepts traffic from ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-policy
  namespace: web-tier
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    ports:
    - protocol: TCP
      port: 80
  egress:
  # Allow DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow access to API tier
  - to:
    - namespaceSelector:
        matchLabels:
          name: api-tier
      podSelector:
        matchLabels:
          tier: api
    ports:
    - protocol: TCP
      port: 8080
---
# API tier - only accepts traffic from frontend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
  namespace: api-tier
spec:
  podSelector:
    matchLabels:
      tier: api
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: web-tier
      podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 8080
  egress:
  # Allow DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow access to database tier
  - to:
    - namespaceSelector:
        matchLabels:
          name: db-tier
      podSelector:
        matchLabels:
          tier: database
    ports:
    - protocol: TCP
      port: 5432
---
# Database tier - only accepts traffic from API
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-policy
  namespace: db-tier
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: api-tier
      podSelector:
        matchLabels:
          tier: api
    ports:
    - protocol: TCP
      port: 5432
  egress:
  # Allow DNS only
  - to: []
    ports:
    - protocol: UDP
      port: 53
```

### Environment Isolation

```yaml
# environment-isolation.yaml
# Production namespace isolation
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    environment: production
    network-policy: isolated
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: production-isolation
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Only allow traffic from production namespace
  - from:
    - namespaceSelector:
        matchLabels:
          environment: production
  # Allow traffic from ingress controller
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
  egress:
  # Allow DNS
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Allow traffic within production
  - to:
    - namespaceSelector:
        matchLabels:
          environment: production
  # Allow HTTPS to external services
  - to: []
    ports:
    - protocol: TCP
      port: 443
```

## Container Network Interface (CNI) Security

### Calico Security Features

```yaml
# calico-global-policy.yaml
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: deny-all-non-system-traffic
spec:
  order: 1000
  selector: projectcalico.org/namespace != 'kube-system'
  types:
  - Ingress
  - Egress
  # Default deny all
---
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: allow-system-traffic
spec:
  order: 100
  selector: projectcalico.org/namespace == 'kube-system'
  types:
  - Ingress
  - Egress
  ingress:
  - action: Allow
  egress:
  - action: Allow
---
# Host endpoint protection
apiVersion: projectcalico.org/v3
kind: HostEndpoint
metadata:
  name: node1-eth0
  labels:
    environment: production
spec:
  interfaceName: eth0
  node: node1
  expectedIPs:
  - 10.0.1.10
---
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: restrict-host-access
spec:
  order: 50
  selector: environment == 'production'
  applyOnForward: true
  preDNAT: true
  types:
  - Ingress
  ingress:
  # Allow SSH from management network
  - action: Allow
    protocol: TCP
    destination:
      ports: [22]
    source:
      nets: ["192.168.1.0/24"]
  # Allow Kubernetes API
  - action: Allow
    protocol: TCP
    destination:
      ports: [6443]
  # Allow kubelet
  - action: Allow
    protocol: TCP
    destination:
      ports: [10250]
```

### Cilium Security Policies

```yaml
# cilium-l7-policy.yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: l7-http-policy
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: web
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: "GET"
          path: "/api/v1/.*"
        - method: "POST"
          path: "/api/v1/users"
          headers:
          - "Content-Type: application/json"
  egress:
  - toEndpoints:
    - matchLabels:
        app: database
    toPorts:
    - ports:
      - port: "5432"
        protocol: TCP
  # Allow DNS
  - toPorts:
    - ports:
      - port: "53"
        protocol: UDP
      rules:
        dns:
        - matchPattern: "*.cluster.local"
        - matchName: "api.example.com"
```

## TLS and Certificate Management

### Mutual TLS (mTLS) Configuration

```yaml
# mtls-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: mtls-certs
  namespace: production
type: kubernetes.io/tls
data:
  ca.crt: LS0tLS1CRUdJTi... # CA certificate
  tls.crt: LS0tLS1CRUdJTi... # Client certificate
  tls.key: LS0tLS1CRUdJTi... # Client private key
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-mtls-config
  namespace: production
data:
  nginx.conf: |
    events {}
    http {
        upstream backend {
            server backend-service:8080;
        }
        
        server {
            listen 443 ssl;
            server_name api.example.com;
            
            # Server certificates
            ssl_certificate /etc/certs/tls.crt;
            ssl_certificate_key /etc/certs/tls.key;
            
            # Client certificate verification
            ssl_client_certificate /etc/certs/ca.crt;
            ssl_verify_client on;
            
            # SSL settings
            ssl_protocols TLSv1.2 TLSv1.3;
            ssl_ciphers ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256;
            ssl_prefer_server_ciphers on;
            
            location / {
                proxy_pass http://backend;
                proxy_set_header X-SSL-Client-Cert $ssl_client_cert;
                proxy_set_header X-SSL-Client-DN $ssl_client_s_dn;
            }
        }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mtls-proxy
  namespace: production
spec:
  replicas: 2
  selector:
    matchLabels:
      app: mtls-proxy
  template:
    metadata:
      labels:
        app: mtls-proxy
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 443
        volumeMounts:
        - name: mtls-certs
          mountPath: /etc/certs
          readOnly: true
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
      volumes:
      - name: mtls-certs
        secret:
          secretName: mtls-certs
      - name: nginx-config
        configMap:
          name: nginx-mtls-config
```

### Certificate Rotation Automation

```yaml
# cert-rotation-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cert-rotation
  namespace: kube-system
spec:
  schedule: "0 2 * * 0"  # Weekly on Sunday at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: cert-rotation-sa
          containers:
          - name: cert-rotator
            image: alpine/openssl
            command:
            - /bin/sh
            - -c
            - |
              # Check certificate expiration
              CERT_FILE="/etc/certs/tls.crt"
              DAYS_LEFT=$(openssl x509 -in $CERT_FILE -noout -enddate | cut -d= -f2 | xargs -I {} date -d "{}" +%s | xargs -I {} echo "scale=0; ({} - $(date +%s)) / 86400" | bc)
              
              if [ $DAYS_LEFT -lt 30 ]; then
                echo "Certificate expires in $DAYS_LEFT days, rotating..."
                # Generate new certificate
                openssl genrsa -out /tmp/new.key 2048
                openssl req -new -key /tmp/new.key -out /tmp/new.csr -subj "/CN=api.example.com"
                openssl x509 -req -in /tmp/new.csr -CA /etc/ca/ca.crt -CAkey /etc/ca/ca.key -out /tmp/new.crt -days 365
                
                # Update secret
                kubectl create secret tls new-mtls-certs --cert=/tmp/new.crt --key=/tmp/new.key --dry-run=client -o yaml | kubectl apply -f -
                
                # Trigger deployment restart
                kubectl rollout restart deployment/mtls-proxy -n production
              else
                echo "Certificate valid for $DAYS_LEFT days"
              fi
            volumeMounts:
            - name: certs
              mountPath: /etc/certs
            - name: ca-certs
              mountPath: /etc/ca
          volumes:
          - name: certs
            secret:
              secretName: mtls-certs
          - name: ca-certs
            secret:
              secretName: ca-certs
          restartPolicy: OnFailure
```

## Network Monitoring and Logging

### Network Traffic Monitoring

```yaml
# network-monitoring.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: network-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: network-monitor
  template:
    metadata:
      labels:
        app: network-monitor
    spec:
      hostNetwork: true
      hostPID: true
      tolerations:
      - key: node-role.kubernetes.io/master
        effect: NoSchedule
      containers:
      - name: network-monitor
        image: nicolaka/netshoot
        command: ["tcpdump"]
        args: ["-i", "any", "-w", "/data/network.pcap", "port 443 or port 80"]
        securityContext:
          privileged: true
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        hostPath:
          path: /var/log/network
          type: DirectoryOrCreate
```

### Network Policy Logging

```yaml
# network-policy-logging.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-network-config
  namespace: logging
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush         1
        Log_Level     info
        Daemon        off
        Parsers_File  parsers.conf
    
    [INPUT]
        Name              tail
        Path              /var/log/calico/cni/*.log
        Parser            json
        Tag               calico.cni
        Refresh_Interval  5
    
    [INPUT]
        Name              tail
        Path              /var/log/syslog
        Parser            syslog
        Tag               syslog
        Refresh_Interval  5
    
    [FILTER]
        Name    grep
        Match   calico.*
        Regex   message denied
    
    [FILTER]
        Name    grep
        Match   syslog
        Regex   message DROP
    
    [OUTPUT]
        Name  es
        Match *
        Host  elasticsearch.logging.svc.cluster.local
        Port  9200
        Index network-security
```

## Best Practices

### 1. Zero Trust Network Architecture

```yaml
# zero-trust-policies.yaml
# Default deny-all policy for every namespace
apiVersion: v1
kind: ConfigMap
metadata:
  name: zero-trust-template
data:
  default-deny.yaml: |
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-all
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      - Egress
---
# Namespace creation webhook to apply default policies
apiVersion: v1
kind: ConfigMap
metadata:
  name: namespace-webhook-config
data:
  webhook.sh: |
    #!/bin/bash
    NAMESPACE=$1
    kubectl apply -f - <<EOF
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: default-deny-all
      namespace: $NAMESPACE
    spec:
      podSelector: {}
      policyTypes:
      - Ingress
      - Egress
    EOF
```

### 2. Principle of Least Privilege

```yaml
# least-privilege-example.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: minimal-access-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  - Egress
  ingress:
  # Only specific source and port
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080  # Only required port
  egress:
  # DNS only
  - to: []
    ports:
    - protocol: UDP
      port: 53
  # Specific database access
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432
  # No wildcard rules, no unnecessary ports
```

### 3. Network Segmentation Testing

```bash
#!/bin/bash
# network-security-test.sh

echo "=== Network Security Testing ==="

# Test default deny policy
echo "Testing default deny policy..."
kubectl run test-pod --image=nicolaka/netshoot --rm -it --restart=Never -- nc -zv google.com 80

# Test specific allow rules
echo "Testing allowed connections..."
kubectl run web-test --image=nicolaka/netshoot --rm -it --restart=Never -l app=web -- nc -zv database-service 5432

# Test cross-namespace communication
echo "Testing cross-namespace policies..."
kubectl run frontend-test --image=nicolaka/netshoot --rm -it --restart=Never -n frontend -l app=frontend -- nc -zv api-service.backend.svc.cluster.local 8080

# Test blocked communication
echo "Testing blocked connections..."
kubectl run blocked-test --image=nicolaka/netshoot --rm -it --restart=Never -- nc -zv internal-service 80

echo "Network security tests completed."
```

### 4. Automated Policy Validation

```yaml
# policy-validation-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: network-policy-validator
  namespace: security-testing
spec:
  template:
    spec:
      containers:
      - name: validator
        image: python:3.9-alpine
        command:
        - python
        - -c
        - |
          import subprocess
          import json
          import sys
          
          def test_policy(namespace, policy_name):
              # Get network policy
              result = subprocess.run(
                  ["kubectl", "get", "networkpolicy", policy_name, "-n", namespace, "-o", "json"],
                  capture_output=True, text=True
              )
              
              if result.returncode != 0:
                  print(f"Error: Policy {policy_name} not found in namespace {namespace}")
                  return False
              
              policy = json.loads(result.stdout)
              
              # Validate policy has both ingress and egress rules
              policy_types = policy.get('spec', {}).get('policyTypes', [])
              if 'Ingress' not in policy_types or 'Egress' not in policy_types:
                  print(f"Warning: Policy {policy_name} doesn't specify both Ingress and Egress")
                  return False
              
              # Check for default deny
              ingress_rules = policy.get('spec', {}).get('ingress', [])
              egress_rules = policy.get('spec', {}).get('egress', [])
              
              if not ingress_rules and not egress_rules:
                  print(f"Info: Policy {policy_name} is default deny-all")
              
              print(f"Policy {policy_name} validation passed")
              return True
          
          # Test all network policies
          namespaces = ["production", "staging", "development"]
          all_passed = True
          
          for ns in namespaces:
              print(f"Testing namespace: {ns}")
              result = subprocess.run(
                  ["kubectl", "get", "networkpolicy", "-n", ns, "-o", "jsonpath={.items[*].metadata.name}"],
                  capture_output=True, text=True
              )
              
              if result.returncode == 0 and result.stdout:
                  policies = result.stdout.split()
                  for policy in policies:
                      if not test_policy(ns, policy):
                          all_passed = False
              else:
                  print(f"Warning: No network policies found in namespace {ns}")
                  all_passed = False
          
          if not all_passed:
              sys.exit(1)
          
          print("All network policy validations passed!")
      restartPolicy: Never
```

## Troubleshooting Network Security

### Common Issues and Solutions

```bash
#!/bin/bash
# network-troubleshooting.sh

echo "=== Network Security Troubleshooting ==="

# Check if CNI supports network policies
echo "Checking CNI capabilities..."
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.containerRuntimeVersion}'
kubectl get daemonsets -n kube-system

# Verify network policy is applied
echo "\nChecking network policies..."
kubectl get networkpolicy -A

# Check pod connectivity
echo "\nTesting pod connectivity..."
kubectl run test-connectivity --image=nicolaka/netshoot --rm -it --restart=Never -- ping -c 3 kubernetes.default.svc.cluster.local

# Check DNS resolution
echo "\nTesting DNS resolution..."
kubectl run test-dns --image=nicolaka/netshoot --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local

# Check service endpoints
echo "\nChecking service endpoints..."
kubectl get endpoints -A

# Check ingress controller logs
echo "\nChecking ingress controller logs..."
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50

# Check for iptables rules (on nodes)
echo "\nChecking iptables rules..."
echo "Run this on each node: sudo iptables -L -n | grep -E '(KUBE|CALICO|CILIUM)'"
```

## References

- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Istio Security](https://istio.io/latest/docs/concepts/security/)
- [Linkerd Security](https://linkerd.io/2/features/automatic-mtls/)
- [Calico Network Security](https://docs.projectcalico.org/security/)
- [Cilium Network Security](https://docs.cilium.io/en/stable/policy/)
- [NGINX Ingress Security](https://kubernetes.github.io/ingress-nginx/user-guide/tls/)

---

**Next**: [Pod and Container Security](../pod-security/) - Learn about securing individual pods and containers.
