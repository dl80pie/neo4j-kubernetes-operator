# OpenShift Anpassungen am Neo4j Operator

Diese Dokumentation beschreibt die durchgeführten Anpassungen am Neo4j Kubernetes Operator für den Einsatz auf Red Hat OpenShift.

## Übersicht der Änderungen

### 1. RBAC-Erweiterungen für OpenShift

**Dateien:**
- `charts/neo4j-operator/templates/clusterrole.yaml`
- `charts/neo4j-operator/templates/role.yaml`

**Änderungen:**
```yaml
# Zusätzliche Berechtigungen für OpenShift Routes
- apiGroups: ["route.openshift.io"]
  resources: ["routes"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]

# Berechtigungen für Deployments/StatefulSets
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets"]
  verbs: ["get", "list", "watch"]
```

**Begründung:** OpenShift Routes (route.openshift.io/v1) erfordern explizite RBAC-Berechtigungen. Der Operator muss Routes erstellen und verwalten können, wenn `spec.service.route.enabled: true` gesetzt ist.

### 2. UBI9 Image-Erkennung für Arbitrary UID

**Datei:** `internal/resources/cluster.go`

**Funktionen modifiziert:**
- `podSecurityContextForCluster()`
- `containerSecurityContextForCluster()`

**Logik:**
```go
// Prüfe ob UBI9-Image verwendet wird
if strings.Contains(cluster.Spec.Image.Tag, "ubi9") || strings.Contains(cluster.Spec.Image.Tag, "ubi") {
    // Für UBI9: Keine feste UID setzen
    return &corev1.PodSecurityContext{
        RunAsNonRoot: ptr.To(true),
        SeccompProfile: &corev1.SeccompProfile{
            Type: corev1.SeccompProfileTypeRuntimeDefault,
        },
        // Kein RunAsUser, RunAsGroup, FSGroup!
    }
}
```

**Begründung:** OpenShift weist jedem Namespace einen UID-Range zu (z.B. 1000970000-1000979999). UBI9-Images unterstützen das Laufen mit beliebigen UIDs aus diesem Range. Feste UIDs (wie 7474) verursachen SCC-Fehler.

### 3. Route DeepCopy Fixes

**Datei:** `internal/resources/route.go`

**Problem:** Kubernetes' `DeepCopyJSON` kann nur mit `map[string]interface{}` und `float64` umgehen, nicht mit `map[string]string` oder `int`/`int32`.

**Fehlermeldungen:**
```
panic: cannot deep copy map[string]string
panic: cannot deep copy int
```

**Lösung:**
```go
// Vorher (fehlerhaft):
labels := map[string]string{"key": "value"}
"labels": labels,  // map[string]string - panic!
"weight": 100,     // int - panic!
"targetPort": targetPort,  // int32 - panic!

// Nachher (korrekt):
labelsMap := make(map[string]interface{}, len(labels))
for k, v := range labels {
    labelsMap[k] = v  // string zu interface{}
}
"labels": labelsMap,  // map[string]interface{}
"weight": float64(100),  // float64
"targetPort": float64(targetPort),  // float64
```

**Wichtige Konvertierungen:**
- `map[string]string` → `map[string]interface{}`
- `int`/`int32` → `float64`

### 4. OpenShift Beispiel-Manifeste

**Neue Dateien:**
- `examples/openshift/cluster-ubi9.yaml` - Cluster mit UBI9 Image
- `examples/openshift/standalone-ubi9.yaml` - Standalone mit UBI9 Image
- `examples/openshift/minimal-cluster.yaml` - Cluster mit festem UID + Custom SCC
- `examples/openshift/neo4j-scc.yaml` - Custom SecurityContextConstraints

**Helm Values:**
- `charts/neo4j-operator/values-openshift.yaml` - OpenShift-spezifische Konfiguration

### 5. Build-Anpassungen für Air-Gapped Umgebungen

**Dockerfile.openshift:**
- Verwendet `registry.access.redhat.com/ubi9/go-toolset:1.22` statt golang:1.24
- Red Hat zertifizierte Base Images für OpenShift-Kompatibilität

## Deployment-Varianten

### Variante A: UBI9 (Empfohlen)

```yaml
spec:
  image:
    repo: neo4j
    tag: 5.26.0-enterprise-ubi9
  service:
    route:
      enabled: true
```

- Keine Custom SCC erforderlich
- Funktioniert mit `restricted-v2` SCC
- Keine feste UID notwendig

### Variante B: Feste UID mit Custom SCC

```yaml
spec:
  image:
    repo: neo4j
    tag: 5.26-enterprise  # Non-UBI
  securityContext:
    runAsUser: 7474
    runAsGroup: 7474
    fsGroup: 7474
```

- Benötigt Custom SCC (`neo4j-scc.yaml`)
- ServiceAccount muss an SCC gebunden werden

## Bekannte Probleme und Lösungen

| Problem | Ursache | Lösung |
|---------|---------|--------|
| `unable to validate against any SCC` | Altes Operator-Image mit fester UID | Neuen Image-Tag bauen und deployen |
| `cannot deep copy map[string]string` | JSON Types in Route | `map[string]interface{}` verwenden |
| `cannot deep copy int` | JSON Types in Route | `float64` für Zahlen verwenden |
| `route.openshift.io forbidden` | Fehlende RBAC | ClusterRole erweitern |

## Build- und Deployment-Workflow

### Testing

### Unit-Tests (auf Build-Host)

```bash
# Alle Unit-Tests
make test-unit

# Nur Route-bezogene Tests
make test-unit TESTARGS="-run Route"

# Oder direkt mit go
go test ./internal/resources/... -v -run "Route"
go test ./internal/controller/... -v -run "Route"
```

### Integration-Tests (auf Build-Host mit Kind)

```bash
# Vollständige Integration-Tests (erstellt Kind-Cluster)
make test-integration

# Nur OpenShift-spezifische Tests
make test-integration TEST_ARGS="-run OpenShift"
```

### Syntax-Check ohne lokales Go

```bash
# Mit Docker
docker run --rm -v $(pwd):/app -w /app golang:1.24-alpine sh -c "go build -o /dev/null ./..."

# Oder mit Podman
podman run --rm -v $(pwd):/app:Z -w /app golang:1.24-alpine sh -c "go build -o /dev/null ./..."
```

### Build-Prozesst (mit Internet):

```bash
# Änderungen committen
git add -A && git commit -m "OpenShift fixes: RBAC, UBI9, Route DeepCopy"

# Image bauen und pushen
./scripts/build-operator.sh --push --tag v1.0.X-openshift
```

### OpenShift-Cluster:

```bash
# Operator deployen
helm upgrade --install neo4j-operator ./charts/neo4j-operator \
  -n neo4j-operator \
  -f ./charts/neo4j-operator/values-openshift.yaml \
  --set image.tag=v1.0.X-openshift

# Cluster deployen
oc apply -f examples/openshift/cluster-ubi9.yaml
```

## Test-Checkliste

- [ ] Operator Pod läuft ohne Fehler
- [ ] `oc get routes -n <namespace>` zeigt Route
- [ ] Pods starten ohne SCC-Fehler
- [ ] Neo4j UI über Route erreichbar
- [ ] Keine RBAC-Fehler in Operator-Logs

## Zukünftige Verbesserungen

- [ ] Automated SCC Detection (prüfe ob `anyuid` verfügbar)
- [ ] Hostname-Validierung für Routes
- [ ] TLS-Termination automatisch basierend auf Cluster-TLS
