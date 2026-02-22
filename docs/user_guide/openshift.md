# OpenShift Deployment Guide

This guide covers deploying the Neo4j Kubernetes Operator on Red Hat OpenShift, including air-gapped environments and SCC-compliant configurations.

## Table of Contents

- [Prerequisites](#prerequisites)
- [OpenShift-Specific Considerations](#openshift-specific-considerations)
- [Deployment Variants](#deployment-variants)
  - [Variant A: UBI9 Image (Recommended)](#variant-a-ubi9-image-recommended)
  - [Variant B: Fixed UID with Custom SCC](#variant-b-fixed-uid-with-custom-scc)
- [Air-Gapped Installation](#air-gapped-installation)
- [RBAC Configuration](#rbac-configuration)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- OpenShift 4.12+ cluster
- `oc` CLI configured
- Helm 3.x (optional but recommended)
- For air-gapped: internal container registry access

## OpenShift-Specific Considerations

### Security Context Constraints (SCC)

OpenShift uses SCCs to control pod security. The Neo4j operator supports two deployment modes:

| Mode | Image | UID Behavior | SCC Required |
|------|-------|--------------|--------------|
| **UBI9** | `neo4j:enterprise-ubi9` | Arbitrary UID (OpenShift assigned) | `restricted-v2` (default) |
| **Standard** | `neo4j:5.26-enterprise` | Fixed UID 7474 | Custom SCC |

### Image Requirements

OpenShift requires images that support arbitrary UIDs. The official Neo4j UBI9 images are certified for OpenShift:

```yaml
# OpenShift-compatible image
image:
  repo: neo4j
  tag: 5.26-enterprise-ubi9  # or 2025.x-enterprise-ubi9
  pullPolicy: IfNotPresent
```

## Deployment Variants

### Variant A: UBI9 Image (Recommended)

This is the simplest approach - no custom SCC required. The UBI9 image automatically adapts to OpenShift's assigned UID.

**1. Install the Operator**

```bash
# Using Helm
helm upgrade --install neo4j-operator ./charts/neo4j-operator \
  -n neo4j-operator \
  --create-namespace \
  -f ./charts/neo4j-operator/values-openshift.yaml

# Or using kubectl/kustomize
oc apply -k config/overlays/openshift
```

**2. Deploy Neo4j Cluster**

```bash
# Create namespace
oc new-project neo4j-cluster

# Apply the UBI9 cluster example
oc apply -f examples/openshift/cluster-ubi9.yaml
```

**Example: `examples/openshift/cluster-ubi9.yaml`**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: neo4j-auth-ubi9
  namespace: neo4j-cluster
type: Opaque
data:
  username: bmVvNGo=  # base64: neo4j
  password: Y2hhbmdlbWU=  # base64: changeme
---
apiVersion: neo4j.neo4j.com/v1alpha1
kind: Neo4jEnterpriseCluster
metadata:
  name: neo4j-cluster-ubi9
  namespace: neo4j-cluster
spec:
  image:
    repo: neo4j
    tag: 5.26-enterprise-ubi9
    pullPolicy: IfNotPresent
  
  topology:
    servers: 3
  
  storage:
    className: lvms-vg1  # Your default StorageClass
    size: 10Gi
    accessMode: ReadWriteOnce
  
  auth:
    adminSecret: neo4j-auth-ubi9
  
  # UBI9 doesn't need custom securityContext - OpenShift handles it
```

**3. Verify Deployment**

```bash
# Check cluster status
oc get neo4jenterprisecluster -n neo4j-cluster

# Check pods
oc get pods -n neo4j-cluster -l app.kubernetes.io/name=neo4j-enterprise-cluster

# View events
oc get events -n neo4j-cluster --field-selector reason=Created
```

### Variant B: Fixed UID with Custom SCC

Use this if you must use non-UBI images (e.g., custom Neo4j builds).

**⚠️ Warning:** This requires a custom SCC and may violate your cluster's security policies. Use only if `anyuid` SCC is not allowed.

**1. Create Custom SCC**

```bash
# Apply the custom SCC
oc apply -f examples/openshift/neo4j-scc.yaml
```

**Example: `examples/openshift/neo4j-scc.yaml`**

```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: neo4j-scc
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostNetwork: false
allowHostPID: false
allowHostPorts: false
allowPrivilegeEscalation: false
allowPrivilegedContainer: false
allowedCapabilities: []
defaultAddCapabilities: []
fsGroup:
  type: MustRunAs
  ranges:
    - min: 7474
      max: 7474
readOnlyRootFilesystem: false
requiredDropCapabilities:
  - ALL
runAsUser:
  type: MustRunAs
  uid: 7474
seLinuxContext:
  type: MustRunAs
seccompProfiles:
  - runtime/default
volumes:
  - configMap
  - downwardAPI
  - emptyDir
  - persistentVolumeClaim
  - projected
  - secret
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: neo4j-scc-role
rules:
  - apiGroups:
      - security.openshift.io
    resources:
      - securitycontextconstraints
    verbs:
      - use
    resourceNames:
      - neo4j-scc
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: neo4j-scc-binding
  namespace: neo4j-cluster
subjects:
  - kind: ServiceAccount
    name: neo4j-cluster-server
    namespace: neo4j-cluster
roleRef:
  kind: ClusterRole
  name: neo4j-scc-role
  apiGroup: rbac.authorization.k8s.io
```

**2. Deploy Cluster with Fixed UID**

```bash
oc apply -f examples/openshift/minimal-cluster.yaml
```

**Example: `examples/openshift/minimal-cluster.yaml`**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: neo4j-auth
  namespace: neo4j-cluster
type: Opaque
data:
  username: bmVvNGo=
  password: Y2hhbmdlbWU=
---
apiVersion: neo4j.neo4j.com/v1alpha1
kind: Neo4jEnterpriseCluster
metadata:
  name: neo4j-cluster
  namespace: neo4j-cluster
spec:
  image:
    repo: neo4j
    tag: 5.26-enterprise
    pullPolicy: IfNotPresent
  
  topology:
    servers: 3
  
  storage:
    className: lvms-vg1
    size: 10Gi
    accessMode: ReadWriteOnce
  
  auth:
    adminSecret: neo4j-auth
  
  # Explicit securityContext required for non-UBI images
  securityContext:
    podSecurityContext:
      runAsUser: 7474
      runAsGroup: 7474
      fsGroup: 7474
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
```

## Air-Gapped Installation

For disconnected OpenShift environments:

### 1. Build Operator Image

On a build host with internet access:

```bash
# Clone repository
git clone https://github.com/neo4j-partners/neo4j-kubernetes-operator.git
cd neo4j-kubernetes-operator

# Build for air-gapped (uses Red Hat UBI go-toolset)
./scripts/build-operator.sh --push --registry harbor.yourcompany.com/library/neo4j
```

### 2. Mirror Neo4j Images

```bash
# Pull and push Neo4j UBI9 image
oc image mirror \
  docker.io/neo4j:5.26-enterprise-ubi9 \
  harbor.yourcompany.com/library/neo4j/neo4j:5.26-enterprise-ubi9
```

### 3. Deploy in Air-Gapped Environment

```bash
# Update values to use internal registry
cat > values-airgap.yaml <<EOF
image:
  registry: harbor.yourcompany.com/library/neo4j
  repository: neo4j-operator
  tag: latest
  pullPolicy: IfNotPresent

neo4jImage:
  registry: harbor.yourcompany.com/library/neo4j
  repository: neo4j
  tag: 5.26-enterprise-ubi9
EOF

# Deploy
helm upgrade --install neo4j-operator ./charts/neo4j-operator \
  -n neo4j-operator \
  --create-namespace \
  -f ./charts/neo4j-operator/values-openshift.yaml \
  -f values-airgap.yaml
```

## RBAC Configuration

The operator requires additional permissions for OpenShift:

### Route Access (included in `values-openshift.yaml`)

```yaml
clusterRole:
  extraRules:
    - apiGroups: ["route.openshift.io"]
      resources: ["routes"]
      verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
    - apiGroups: ["apps"]
      resources: ["deployments", "statefulsets"]
      verbs: ["get", "list", "watch"]
```

### Verify RBAC

```bash
# Check ClusterRole
oc describe clusterrole neo4j-operator

# Check operator logs for permission errors
oc logs -n neo4j-operator deployment/neo4j-operator | grep -i "forbidden"
```

## Troubleshooting

### Pod fails with SCC error

```
unable to validate against any security context constraint
```

**Cause:** Operator is using old image or `cluster.Spec.Image.Tag` doesn't contain "ubi9"

**Solution:**
1. Verify operator image version: `oc get deployment neo4j-operator -n neo4j-operator -o yaml | grep image:`
2. For UBI9: Ensure tag contains "ubi9" (e.g., `5.26-enterprise-ubi9`)
3. For non-UBI: Apply custom SCC from Variant B

### Image pull errors in air-gapped

**Solution:**
```bash
# Verify image exists in internal registry
oc image info harbor.yourcompany.com/library/neo4j/neo4j-operator:latest

# Check pull secrets
oc get secret -n neo4j-operator | grep pull

# Add pull secret if needed
oc create secret docker-registry neo4j-pull-secret \
  --docker-server=harbor.yourcompany.com \
  --docker-username=USER \
  --docker-password=PASS \
  -n neo4j-operator
```

### Operator fails to create StatefulSet

```bash
# Check operator logs
oc logs -n neo4j-operator deployment/neo4j-operator -f

# Check CRD status
oc get crd neo4jenterpriseclusters.neo4j.neo4j.com -o yaml | grep -A 5 conditions

# Verify cluster resource
oc get neo4jenterprisecluster -n neo4j-cluster -o yaml
```

## Quick Reference

### Commands Cheat Sheet

```bash
# Operator management
oc get pods -n neo4j-operator
oc logs -n neo4j-operator deployment/neo4j-operator -f
oc rollout restart deployment neo4j-operator -n neo4j-operator

# Cluster management
oc get neo4jenterprisecluster -A
oc get pods -n neo4j-cluster
oc describe pod -n neo4j-cluster neo4j-cluster-server-0

# SCC verification
oc get scc | grep neo4j
oc get rolebinding -n neo4j-cluster neo4j-scc-binding

# Debug pod creation
oc get events -n neo4j-cluster --field-selector type=Warning
```

### File Locations

| File | Purpose |
|------|---------|
| `examples/openshift/cluster-ubi9.yaml` | UBI9 cluster (recommended) |
| `examples/openshift/standalone-ubi9.yaml` | UBI9 standalone |
| `examples/openshift/minimal-cluster.yaml` | Fixed UID cluster |
| `examples/openshift/neo4j-scc.yaml` | Custom SCC for fixed UID |
| `charts/neo4j-operator/values-openshift.yaml` | OpenShift Helm values |

## See Also

- [Installation Guide](installation.md) - General operator installation
- [Security Guide](security.md) - Security best practices
- [Troubleshooting Guide](troubleshooting/troubleshooting.md) - Common issues
