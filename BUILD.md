# Neo4j Enterprise Operator - Build Anleitung

## Übersicht

Diese Anleitung beschreibt das Bauen des Neo4j Enterprise Operator Docker Images für OpenShift mit Go 1.24.

## Voraussetzungen

- Docker oder Podman
- Zugriff auf eine Container Registry (z.B. harbor.pietsch.uk)
- Go 1.24+ (für lokale Builds optional)
- kubectl / oc CLI

## Schneller Build

### Mit Podman (empfohlen für OpenShift)

```bash
# Build-Skript verwenden
./scripts/build-operator.sh

# Oder manuell:
podman build \
  -f Dockerfile.openshift \
  -t neo4j-operator:latest \
  -t neo4j-operator:v1.0.0-openshift \
  --build-arg VERSION=v1.0.0 \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  --build-arg VCS_REF=$(git rev-parse --short HEAD) \
  .

# Tag für Registry
podman tag neo4j-operator:latest harbor.pietsch.uk/library/neo4j/neo4j-operator:v1.0.0-openshift

# Push
podman push harbor.pietsch.uk/library/neo4j/neo4j-operator:v1.0.0-openshift
```

### Mit Docker

```bash
# Multi-Stage Build
docker build \
  -f Dockerfile.openshift \
  -t neo4j-operator:v1.0.0-openshift \
  --build-arg VERSION=v1.0.0 \
  --build-arg BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  --build-arg VCS_REF=$(git rev-parse --short HEAD) \
  .

# Für Multi-Arch (AMD64 + ARM64)
docker buildx build \
  -f Dockerfile.openshift \
  -t harbor.pietsch.uk/library/neo4j/neo4j-operator:v1.0.0-openshift \
  --platform linux/amd64,linux/arm64 \
  --push \
  .
```

## Image Details

### Basis-Images

| Stage | Image | Zweck |
|-------|-------|-------|
| Build | `registry.access.redhat.com/ubi9/ubi:latest` + Go 1.24 | Red Hat UBI9 mit Go 1.24 |
| Runtime | `registry.access.redhat.com/ubi9/ubi-micro:latest` | Minimaler Runtime für OpenShift |

### Features des Images

- **Go 1.24**: Manuell installiert auf UBI9 (erforderlich laut go.mod)
- **UBI9 Micro**: Red Hat Universal Base Image - optimiert für OpenShift
- **Multi-Stage Build**: Optimierte Image-Größe (~50MB statt ~1GB)
- **Arbitrary UID Support**: Kompatibel mit OpenShift restricted-v2 SCC
- **CVE-freie Basis**: Regelmäßig aktualisierte Red Hat Base Images

## OpenShift Anpassungen

Das Image und Helm Chart enthalten folgende OpenShift-optimierte Änderungen:

1. **Arbitrary UID Support**: Container läuft mit beliebiger UID aus Namespace-Range
2. **restricted-v2 SCC Kompatibilität**: Keine privilegierten Capabilities
3. **UBI Base Image**: Red Hat zertifiziertes Base Image
4. **SecurityContext**: 
   - `allowPrivilegeEscalation: false`
   - `capabilities.drop: ALL`
   - `readOnlyRootFilesystem: true`
   - `runAsNonRoot: true`
   - Kein fester `runAsUser` (OpenShift weist UID zu)

## Helm Deployment auf OpenShift

### Installation

```bash
# Namespace erstellen
oc new-project neo4j-operator

# Harbor Pull Secret erstellen (falls benötigt)
oc create secret docker-registry harbor-pull-secret \
  --docker-server=harbor.pietsch.uk \
  --docker-username=<username> \
  --docker-password=<password>

# Operator installieren mit OpenShift Values
helm upgrade --install neo4j-operator ./charts/neo4j-operator \
  -n neo4j-operator \
  -f ./charts/neo4j-operator/values-openshift.yaml

# Status prüfen
oc get pods -n neo4j-operator
oc logs -n neo4j-operator deployment/neo4j-operator -f
```

### SCC Prüfung

```bash
# SCC-Kompatibilität testen
oc adm policy who-can use scc restricted-v2

# ServiceAccount SCC prüfen
oc get pod -n neo4j-operator -o yaml | grep -A5 securityContext

# Logs prüfen
oc logs -n neo4j-operator deployment/neo4j-operator
```

## Registry Upload

### Harbor (bei pietsch.uk)

```bash
# Login
podman login harbor.pietsch.uk

# Tag und Push
podman tag neo4j-operator:v1.0.0-openshift \
  harbor.pietsch.uk/library/neo4j/neo4j-operator:v1.0.0-openshift

podman push harbor.pietsch.uk/library/neo4j/neo4j-operator:v1.0.0-openshift

# Optional: Latest tag aktualisieren
podman tag neo4j-operator:v1.0.0-openshift \
  harbor.pietsch.uk/library/neo4j/neo4j-operator:latest

podman push harbor.pietsch.uk/library/neo4j/neo4j-operator:latest
```

## Fehlerbehebung

### Problem: Pod startet nicht mit "CreateContainerConfigError"

**Ursache**: SecurityContext nicht kompatibel mit SCC

**Lösung**: 
```bash
# Prüfen welche SCC verwendet wird
oc get pod <pod-name> -o yaml | grep scc

# Falls nötig, restricted-v2 explizit zuweisen
oc adm policy add-scc-to-user restricted-v2 \
  system:serviceaccount:neo4j-operator:neo4j-operator
```

### Problem: Image Pull Error

**Lösung**:
```bash
# Pull Secret prüfen
oc get secret harbor-pull-secret -o yaml

# Secret zum ServiceAccount hinzufügen
oc secrets link neo4j-operator harbor-pull-secret --for=pull
```

### Problem: Permission Denied beim Schreiben

**Ursache**: readOnlyRootFilesystem ist aktiviert

**Lösung**: Für temporäre Dateien emptyDir Volume verwenden:
```yaml
volumes:
  - name: tmp
    emptyDir: {}
volumeMounts:
  - name: tmp
    mountPath: /tmp
```

## Neo4j Cluster Deployment

Nach Installation des Operators:

```bash
# Neo4j Enterprise Cluster erstellen
oc apply -f examples/cluster/minimal-cluster.yaml

# Status prüfen
oc get neo4jenterprisecluster
oc get pods -l app.kubernetes.io/component=neo4j
```

## Versions-History

| Version | Go | Basis-Image | Änderungen |
|---------|-----|-------------|------------|
| v1.0.0-openshift | 1.24 | UBI9 Micro | OpenShift SCC Support, Arbitrary UID |
| dev | 1.24 | distroless | Baseline für Kubernetes |

## Weiterführende Links

- [OpenShift Deployment Examples](./examples/openshift/)
- [Helm Chart Konfiguration](./charts/neo4j-operator/values-openshift.yaml)
- [CRD Dokumentation](./docs/api_reference/)
- [User Guide](./docs/user_guide/)
