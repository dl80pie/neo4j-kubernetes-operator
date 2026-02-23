# Detaillierte Übersicht der OpenShift-Anpassungen

## 1. RBAC-Erweiterungen

### 1.1 `charts/neo4j-operator/templates/clusterrole.yaml`

**Zeilen hinzugefügt (nach Zeile 64 und 186):**

```yaml
# OpenShift Routes Support (route.openshift.io/v1)
- apiGroups:
    - route.openshift.io
  resources:
    - routes
  verbs:
    - get
    - list
    - watch
    - create
    - update
    - patch
    - delete

# Deployment/StatefulSet Zugriff für Operator
- apiGroups:
    - apps
  resources:
    - deployments
    - statefulsets
  verbs:
    - get
    - list
    - watch
```

**Begründung:**
- OpenShift Routes erfordern explizite RBAC-Berechtigungen (nicht Teil der Standard-Kubernetes-API)
- Der Operator erstellt Routes wenn `spec.service.route.enabled: true`
- Deployments/StatefulSets Zugriff für Status-Abfragen

### 1.2 `charts/neo4j-operator/templates/role.yaml`

**Zeilen hinzugefügt (nach Zeile 24):**

```yaml
- apiGroups:
    - apps
  resources:
    - deployments
  verbs:
    - get
    - list
    - watch
```

**Begründung:** Gleiche Berechtigungen für namespace-scoped Mode.

---

## 2. Core Operator-Logik

### 2.1 `internal/resources/cluster.go`

**Funktion `podSecurityContextForCluster()` (Zeile 134-153):**

**Vorher:**
```go
func podSecurityContextForCluster(cluster *neo4jv1alpha1.Neo4jEnterpriseCluster) *corev1.PodSecurityContext {
	if cluster.Spec.SecurityContext != nil && cluster.Spec.SecurityContext.PodSecurityContext != nil {
		return cluster.Spec.SecurityContext.PodSecurityContext
	}
	return defaultPodSecurityContext
}
```

**Nachher:**
```go
func podSecurityContextForCluster(cluster *neo4jv1alpha1.Neo4jEnterpriseCluster) *corev1.PodSecurityContext {
	// Wenn PodSecurityContext explizit gesetzt ist, verwende diesen
	if cluster.Spec.SecurityContext != nil && cluster.Spec.SecurityContext.PodSecurityContext != nil {
		return cluster.Spec.SecurityContext.PodSecurityContext
	}
	
	// Prüfe ob UBI9-Image verwendet wird (unterstützt arbitrary UID)
	if strings.Contains(cluster.Spec.Image.Tag, "ubi9") || strings.Contains(cluster.Spec.Image.Tag, "ubi") {
		// Für UBI9: Keine feste UID setzen - OpenShift weist UID aus namespace range zu
		return &corev1.PodSecurityContext{
			RunAsNonRoot: ptr.To(true),
			SeccompProfile: &corev1.SeccompProfile{
				Type: corev1.SeccompProfileTypeRuntimeDefault,
			},
		}
	}
	
	// Standard: Verwende feste UID 7474 (für nicht-UBI Images)
	return defaultPodSecurityContext
}
```

**Funktion `containerSecurityContextForCluster()` (Zeile 155-176):**

**Vorher:**
```go
func containerSecurityContextForCluster(cluster *neo4jv1alpha1.Neo4jEnterpriseCluster) *corev1.SecurityContext {
	if cluster.Spec.SecurityContext != nil && cluster.Spec.SecurityContext.ContainerSecurityContext != nil {
		return cluster.Spec.SecurityContext.ContainerSecurityContext
	}
	return defaultContainerSecurityContext
}
```

**Nachher:**
```go
func containerSecurityContextForCluster(cluster *neo4jv1alpha1.Neo4jEnterpriseCluster) *corev1.SecurityContext {
	// Wenn ContainerSecurityContext explizit gesetzt ist, verwende diesen
	if cluster.Spec.SecurityContext != nil && cluster.Spec.SecurityContext.ContainerSecurityContext != nil {
		return cluster.Spec.SecurityContext.ContainerSecurityContext
	}
	
	// Prüfe ob UBI9-Image verwendet wird (unterstützt arbitrary UID)
	if strings.Contains(cluster.Spec.Image.Tag, "ubi9") || strings.Contains(cluster.Spec.Image.Tag, "ubi") {
		// Für UBI9: Keine feste UID setzen - OpenShift weist UID aus namespace range zu
		return &corev1.SecurityContext{
			RunAsNonRoot:             ptr.To(true),
			AllowPrivilegeEscalation: ptr.To(false),
			ReadOnlyRootFilesystem:   ptr.To(false),
			Capabilities: &corev1.Capabilities{
				Drop: []corev1.Capability{"ALL"},
			},
		}
	}
	
	// Standard: Verwende feste UID 7474 (für nicht-UBI Images)
	return defaultContainerSecurityContext
}
```

**Begründung:**
- UBI9 Images (Red Hat Universal Base Image) unterstützen das Laufen mit beliebigen UIDs
- OpenShift weist jedem Namespace einen UID-Range zu (z.B. 1000970000-1000979999)
- Feste UID 7474 verursacht SCC-Fehler: "7474 is not an allowed group"
- Erkennung via String-Prüfung auf "ubi9" oder "ubi" im Image-Tag

---

## 3. OpenShift Route DeepCopy Fixes

### 3.1 `internal/resources/route.go`

**Komplette Überarbeitung der `buildRoute()` Funktion:**

**Vorher:**
```go
func buildRoute(name, namespace, serviceName string, labels map[string]string, annotations map[string]string, host, path string, targetPort int32, tls *neo4jv1alpha1.RouteTLSSpec) *unstructured.Unstructured {
	if path == "" {
		path = "/"
	}
	if targetPort == 0 {
		targetPort = HTTPPort
	}

	route := &unstructured.Unstructured{
		Object: map[string]interface{}{
			"apiVersion": "route.openshift.io/v1",
			"kind":       "Route",
			"metadata": map[string]interface{}{
				"name":        name,
				"namespace":   namespace,
				"labels":      labels,        // ❌ map[string]string - panic!
				"annotations": annotations,   // ❌ map[string]string - panic!
			},
			"spec": map[string]interface{}{
				"to": map[string]interface{}{
					"kind":   "Service",
					"name":   serviceName,
					"weight": 100,               // ❌ int - panic!
				},
				"port": map[string]interface{}{
					"targetPort": targetPort,   // ❌ int32 - panic!
				},
				"path": path,
			},
		},
	}
	// ...
}
```

**Nachher:**
```go
func buildRoute(name, namespace, serviceName string, labels map[string]string, annotations map[string]string, host, path string, targetPort int32, tls *neo4jv1alpha1.RouteTLSSpec) *unstructured.Unstructured {
	if path == "" {
		path = "/"
	}
	if targetPort == 0 {
		targetPort = HTTPPort
	}

	// Ensure labels and annotations are not nil to avoid DeepCopy panic
	if labels == nil {
		labels = map[string]string{}
	}
	if annotations == nil {
		annotations = map[string]string{}
	}

	// Convert to map[string]interface{} for unstructured object
	labelsMap := make(map[string]interface{}, len(labels))
	for k, v := range labels {
		labelsMap[k] = v
	}
	annotationsMap := make(map[string]interface{}, len(annotations))
	for k, v := range annotations {
		annotationsMap[k] = v
	}

	route := &unstructured.Unstructured{
		Object: map[string]interface{}{
			"apiVersion": "route.openshift.io/v1",
			"kind":       "Route",
			"metadata": map[string]interface{}{
				"name":        name,
				"namespace":   namespace,
				"labels":      labelsMap,        // ✅ map[string]interface{}
				"annotations": annotationsMap,   // ✅ map[string]interface{}
			},
			"spec": map[string]interface{}{
				"to": map[string]interface{}{
					"kind":   "Service",
					"name":   serviceName,
					"weight": float64(100),         // ✅ float64
				},
				"port": map[string]interface{}{
					"targetPort": float64(targetPort),  // ✅ float64
				},
				"path": path,
			},
		},
	}
	// ...
}
```

**Fehlermeldungen die behoben wurden:**
```
panic: cannot deep copy map[string]string [recovered]
panic: cannot deep copy int [recovered]
```

**Begründung:**
- Kubernetes `runtime.DeepCopyJSONValue()` unterstützt nur:
  - `map[string]interface{}`
  - `[]interface{}`
  - `string`
  - `float64` (für Zahlen)
  - `bool`
  - `nil`
- Keine Unterstützung für `map[string]string`, `int`, `int32`, `int64`
- Unstructured Objects müssen JSON-kompatibel sein

---

## 4. OpenShift Beispiel-Manifeste

### 4.1 `examples/openshift/cluster-ubi9.yaml` (NEU)

**Inhalt:**
- Neo4jEnterpriseCluster mit UBI9 Image
- Keine feste SecurityContext (wird automatisch gesetzt)
- Route aktiviert: `service.route.enabled: true`
- StorageClass: `lvms-vg1`

### 4.2 `examples/openshift/standalone-ubi9.yaml` (NEU)

**Inhalt:**
- Neo4jEnterpriseStandalone mit UBI9 Image
- Route: `route.enabled: true` (Top-Level, nicht unter service)

### 4.3 `examples/openshift/minimal-cluster.yaml` (NEU)

**Inhalt:**
- Cluster mit Standard-Image (nicht UBI9)
- Expliziter SecurityContext mit UID 7474
- Benötigt Custom SCC

### 4.4 `examples/openshift/neo4j-scc.yaml` (NEU)

**Inhalt:**
- SecurityContextConstraints für UID 7474
- ClusterRole für SCC-Nutzung
- RoleBinding für ServiceAccount

### 4.5 `examples/openshift/standalone.yaml` (MODIFIZIERT)

**Änderungen:**
- `apiVersion` korrigiert: `neo4j.neo4j.com/v1alpha1`
- `image` Format korrigiert: `repo`, `tag`, `pullPolicy`
- `storage` Format korrigiert: `className`, `size`
- Secret `data` statt `stringData` mit base64

---

## 5. Helm Values

### 5.1 `charts/neo4j-operator/values-openshift.yaml` (NEU)

**Inhalt:**
```yaml
clusterRole:
  extraRules:
    - apiGroups: ["route.openshift.io"]
      resources: ["routes"]
      verbs: ["*"]
    - apiGroups: ["apps"]
      resources: ["deployments", "statefulsets"]
      verbs: ["get", "list", "watch"]

image:
  pullPolicy: IfNotPresent
```

---

## 6. Build-Infrastruktur

### 6.1 `Dockerfile.openshift` (MODIFIZIERT)

**Änderungen:**
```dockerfile
# Vorher:
FROM golang:1.24-alpine AS builder

# Nachher:
FROM registry.access.redhat.com/ubi9/go-toolset:1.22 AS builder
```

**Begründung:**
- Red Hat UBI Images für OpenShift-Zertifizierung
- Air-gapped Kompatibilität (kein Docker Hub Zugriff nötig)

### 6.2 `BUILD.md` (MODIFIZIERT)

**Hinzugefügte Sektionen:**
- OpenShift-spezifischer Build-Workflow
- Red Hat Registry Anmeldung
- Image Push zu internem Registry

### 6.3 `.gitignore` (MODIFIZIERT)

**Hinzugefügt:**
```
# Go toolchain for air-gapped builds
go1.24*.tar.gz
```

---

## 7. Dokumentation

### 7.1 `docs/user_guide/openshift.md` (NEU)

**Inhalt:**
- Vollständige OpenShift Deployment-Anleitung
- Varianten A (UBI9) und B (Feste UID)
- Air-gapped Installation
- Troubleshooting-Sektion

### 7.2 `OPENSHIFT_CHANGES.md` (NEU)

**Inhalt:**
- Übersicht aller technischen Änderungen
- Problem-Lösung-Matrix
- Build-Workflow

### 7.3 Diese Datei: `OPENSHIFT_CHANGES_DETAILED.md`

---

## Zusammenfassung der betroffenen Dateien

| Datei | Änderungstyp | Zeilen geändert |
|-------|--------------|-----------------|
| `charts/neo4j-operator/templates/clusterrole.yaml` | Erweitert | ~20 hinzugefügt |
| `charts/neo4j-operator/templates/role.yaml` | Erweitert | ~10 hinzugefügt |
| `internal/resources/cluster.go` | Modifiziert | 2 Funktionen |
| `internal/resources/route.go` | Modifiziert | 1 Funktion komplett |
| `examples/openshift/cluster-ubi9.yaml` | Neu | 70 Zeilen |
| `examples/openshift/standalone-ubi9.yaml` | Neu | 60 Zeilen |
| `examples/openshift/minimal-cluster.yaml` | Neu | 65 Zeilen |
| `examples/openshift/neo4j-scc.yaml` | Neu | 60 Zeilen |
| `examples/openshift/standalone.yaml` | Modifiziert | 46 Zeilen |
| `charts/neo4j-operator/values-openshift.yaml` | Neu | 40 Zeilen |
| `Dockerfile.openshift` | Modifiziert | Basis-Image |
| `BUILD.md` | Modifiziert | OpenShift Sektion |
| `.gitignore` | Modifiziert | Go Archive |
| `docs/user_guide/openshift.md` | Neu | 350 Zeilen |
| `OPENSHIFT_CHANGES.md` | Neu | 200 Zeilen |
| Diese Datei | Neu | 450 Zeilen |

---

## Test-Status

| Komponente | Status | Hinweis |
|------------|--------|---------|
| RBAC | ✅ OK | Routes werden erkannt |
| UBI9 UID | ⚠️ Pending | Neuer Image-Tag nötig |
| Route DeepCopy | ⚠️ Pending | `float64` Fix muss gebaut werden |
| Beispiele | ✅ OK | Alle 4 Varianten erstellt |
| Dokumentation | ✅ OK | Vollständig |
