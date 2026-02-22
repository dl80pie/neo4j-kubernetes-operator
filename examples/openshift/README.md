# Neo4j Enterprise Operator - OpenShift Deployment

Diese Beispiele zeigen die Deployment-Optionen für den Neo4j Enterprise Operator auf OpenShift.

## Voraussetzungen

- OpenShift 4.12+
- `oc` CLI installiert und konfiguriert
- Zugriff auf Container Registry (z.B. harbor.pietsch.uk)
- Helm 3.x

## Quick Start

### 1. Namespace und Pull Secret erstellen

```bash
# Namespace erstellen
oc new-project neo4j-operator

# Harbor Pull Secret erstellen
oc create secret docker-registry harbor-pull-secret \
  --docker-server=harbor.pietsch.uk \
  --docker-username=<username> \
  --docker-password=<password>
```

### 2. Operator installieren

```bash
# Mit Helm
helm upgrade --install neo4j-operator ../../charts/neo4j-operator \
  -n neo4j-operator \
  -f ../../charts/neo4j-operator/values-openshift.yaml
```

### 3. Neo4j Cluster erstellen

```bash
# Minimaler 3-Node Cluster
oc apply -f minimal-cluster.yaml

# Status prüfen
oc get neo4jenterprisecluster
oc get pods -l app.kubernetes.io/component=neo4j
```

## Beispiele

| Datei | Beschreibung |
|-------|--------------|
| `minimal-cluster.yaml` | Minimaler 3-Node Enterprise Cluster |
| `standalone.yaml` | Single-Node Standalone Instanz |
| `cluster-with-storage.yaml` | Cluster mit persistentem Storage |
| `cluster-with-backup.yaml` | Cluster mit Backup-Konfiguration |

## OpenShift-spezifische Konfiguration

### Security Context Constraints (SCC)

Der Operator und Neo4j Pods laufen mit `restricted-v2` SCC:

- Keine Root-Rechte
- Arbitrary UID aus Namespace-Range
- Keine privilegierten Capabilities
- Read-only Root Filesystem (wo möglich)

### Storage Classes

Für persistenten Storage empfohlen:

```yaml
spec:
  storage:
    data:
      size: 10Gi
      storageClassName: ""  # Verwendet Default StorageClass
```

### Routes

Für externen Zugriff auf Neo4j Browser:

```bash
oc expose svc/neo4j-cluster-lb --port=7474
```

## Troubleshooting

### Pod startet nicht

```bash
# Events prüfen
oc get events --sort-by='.lastTimestamp'

# SCC prüfen
oc get pod <pod-name> -o yaml | grep scc

# Logs prüfen
oc logs <pod-name>
```

### Cluster bildet sich nicht

```bash
# Cluster Status
oc describe neo4jenterprisecluster <cluster-name>

# Neo4j Logs
oc logs -l app.kubernetes.io/instance=<cluster-name> -c neo4j
```
