# Chapter 4 - Securing Kubernetes: Code Examples

This directory contains practical, production-ready code examples for implementing security in Kubernetes clusters. All examples follow security best practices and demonstrate real-world scenarios.

## Directory Structure

```
Code/
├── service-accounts/              # Service Account configurations
│   ├── basic-service-account.yaml # Basic SA setup with RBAC
│   ├── token-projection.yaml      # SA token projection examples
│   └── workload-identity.yaml     # Cloud workload identity integration
├── network-policies/              # Network security policies
│   ├── default-deny.yaml          # Default deny-all policies
│   ├── three-tier-app.yaml        # 3-tier application network isolation
│   └── namespace-isolation.yaml   # Cross-namespace communication
├── secrets/                       # Secrets management examples
│   ├── basic-secrets.yaml         # Native Kubernetes secrets
│   ├── external-secrets.yaml      # External secrets operator
│   └── vault-integration.yaml     # HashiCorp Vault integration
├── pod-security/                  # Pod and container security
│   ├── security-contexts.yaml     # Security context examples
│   ├── pod-security-standards.yaml # Pod Security Standards
│   └── runtime-security.yaml      # Runtime security with gVisor/Kata
├── apparmor/                      # AppArmor profiles and setup
│   ├── nginx-profile.yaml         # NGINX AppArmor profile
│   ├── application-profile.yaml   # Custom application profile
│   └── installation-setup.yaml    # AppArmor installation DaemonSet
└── multi-tenancy/                 # Multi-tenancy implementations
    ├── namespace-tenant.yaml      # Namespace-based multi-tenancy
    ├── virtual-cluster.yaml       # vcluster virtual clusters
    ├── hierarchical-namespaces.yaml # HNC hierarchical namespaces
    └── tenant-automation.yaml     # Automated tenant onboarding
```

## Quick Start

### Prerequisites

- Kubernetes cluster (v1.25+)
- kubectl configured and working
- Cluster admin privileges
- Basic understanding of Kubernetes security concepts

### Basic Security Setup

1. **Deploy Default Security Policies**:
   ```bash
   # Apply default deny network policies
   kubectl apply -f network-policies/default-deny.yaml
   
   # Set up basic service accounts with RBAC
   kubectl apply -f service-accounts/basic-service-account.yaml
   ```

2. **Implement Pod Security Standards**:
   ```bash
   # Create namespace with restricted pod security
   kubectl apply -f pod-security/pod-security-standards.yaml
   ```

3. **Configure Secrets Management**:
   ```bash
   # Deploy basic secrets (for development)
   kubectl apply -f secrets/basic-secrets.yaml
   
   # For production, use external secrets
   kubectl apply -f secrets/external-secrets.yaml
   ```

### Advanced Security Features

4. **Enable AppArmor Security**:
   ```bash
   # Install AppArmor profiles on nodes
   kubectl apply -f apparmor/installation-setup.yaml
   
   # Deploy AppArmor-secured applications
   kubectl apply -f apparmor/nginx-profile.yaml
   ```

5. **Set Up Multi-Tenancy**:
   ```bash
   # Create namespace-based tenant
   kubectl apply -f multi-tenancy/namespace-tenant.yaml
   
   # Or deploy virtual cluster for stronger isolation
   kubectl apply -f multi-tenancy/virtual-cluster.yaml
   ```

## Security Configuration Guidelines

### Service Accounts
- **Always use dedicated service accounts** for applications
- **Disable token auto-mounting** unless required
- **Use workload identity** for cloud integrations
- **Implement least privilege RBAC** policies

### Network Security
- **Start with default deny-all** network policies
- **Explicitly allow required communication** only
- **Implement network segmentation** by tiers/environments
- **Use namespace isolation** for tenant separation

### Pod Security
- **Enforce Pod Security Standards** (baseline/restricted)
- **Use non-root containers** wherever possible
- **Enable read-only root filesystems**
- **Drop all capabilities** and add only required ones
- **Use security runtimes** (gVisor/Kata) for sensitive workloads

### Secrets Management
- **Never store secrets in plain text** or container images
- **Use external secret management** systems in production
- **Rotate secrets regularly** with automation
- **Encrypt secrets at rest** with proper key management

### Multi-Tenancy
- **Choose appropriate isolation level** based on trust boundaries
- **Implement resource quotas** and limits for all tenants
- **Use network policies** for tenant isolation
- **Monitor and audit** tenant activities

## Testing Security Configurations

### Network Policy Testing
```bash
# Test network connectivity
kubectl run test-pod --image=nicolaka/netshoot --rm -it --restart=Never -- nc -zv target-service 80

# Verify network policies are working
kubectl run blocked-test --image=nicolaka/netshoot --rm -it --restart=Never -- nc -zv blocked-service 80
```

### RBAC Testing
```bash
# Test service account permissions
kubectl auth can-i create pods --as=system:serviceaccount:production:webapp-sa

# List all permissions for a service account
kubectl auth can-i --list --as=system:serviceaccount:production:webapp-sa
```

### Pod Security Testing
```bash
# Try to create a privileged pod (should fail in restricted namespace)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: privileged-test
  namespace: restricted-namespace
spec:
  containers:
  - name: test
    image: nginx
    securityContext:
      privileged: true
EOF
```

## Security Monitoring

### Audit Configuration
```bash
# Check audit logs for security events
kubectl logs -n kube-system kube-apiserver-* | grep audit

# Monitor failed authentication attempts
kubectl get events --field-selector reason=Forbidden
```

### Runtime Security
```bash
# Deploy Falco for runtime monitoring
kubectl apply -f pod-security/runtime-security.yaml

# Check Falco alerts
kubectl logs -n falco-system daemonset/falco
```

## Troubleshooting

### Common Issues

1. **Pods fail to start with security context errors**:
   - Check Pod Security Standards enforcement
   - Verify security context configuration
   - Review AppArmor profile restrictions

2. **Network policies blocking required communication**:
   - Verify network policy selectors
   - Check DNS resolution (ensure DNS egress allowed)
   - Test connectivity step by step

3. **RBAC permission denied errors**:
   - Verify service account exists
   - Check role and role binding configuration
   - Test permissions with `kubectl auth can-i`

4. **Secrets not accessible by pods**:
   - Verify secret exists in correct namespace
   - Check RBAC permissions for secret access
   - Ensure correct secret key names

### Debug Commands
```bash
# Debug pod security context
kubectl describe pod <pod-name>
kubectl get pod <pod-name> -o yaml | grep -A 20 securityContext

# Debug network policies
kubectl describe networkpolicy <policy-name>
kubectl get networkpolicy -A

# Debug RBAC
kubectl describe role <role-name>
kubectl describe rolebinding <binding-name>

# Debug secrets
kubectl describe secret <secret-name>
kubectl get secret <secret-name> -o yaml
```

## Best Practices Summary

### Security Checklist
- [ ] Default deny network policies implemented
- [ ] Pod Security Standards enforced
- [ ] Service accounts use least privilege RBAC
- [ ] Secrets managed externally or encrypted at rest
- [ ] Container images scanned for vulnerabilities
- [ ] Runtime security monitoring enabled
- [ ] Multi-tenancy isolation configured
- [ ] Audit logging enabled and monitored
- [ ] Regular security assessments performed
- [ ] Incident response procedures documented

### Defense in Depth
Implement security at multiple layers:
1. **Infrastructure**: Secure nodes and network
2. **Cluster**: RBAC, network policies, admission controllers
3. **Namespace**: Resource quotas, security policies
4. **Pod**: Security contexts, runtime security
5. **Container**: Image scanning, minimal base images
6. **Application**: Secure coding practices, dependency management

## Contributing

When adding new security examples:
1. Follow the established directory structure
2. Include comprehensive comments explaining security configurations
3. Test examples in multiple environments
4. Document any prerequisites or limitations
5. Follow Kubernetes security best practices
6. Include both basic and advanced examples

## References

- [Kubernetes Security Documentation](https://kubernetes.io/docs/concepts/security/)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Secrets Management](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Multi-Tenancy](https://kubernetes.io/docs/concepts/security/multi-tenancy/)

---

**Remember**: Security is not a one-time setup but an ongoing process. Regularly review and update your security configurations as your applications and threat landscape evolve.
