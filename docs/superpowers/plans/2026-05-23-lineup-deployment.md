# Lineup Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Helm chart under `apps/lineup/` so ArgoCD auto-deploys `ghcr.io/markis/lineup:latest` and exposes it at `lineup.markis.network`.

**Architecture:** Three Kubernetes resources — a Deployment, a ClusterIP Service, and a Traefik IngressRoute — packaged as a Helm chart. ArgoCD's ApplicationSet discovers any chart in `apps/` and deploys it automatically; no manual ArgoCD registration needed.

**Tech Stack:** Helm v2 chart, Kubernetes, Traefik IngressRoute (traefik.io/v1alpha1)

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `apps/lineup/Chart.yaml` | Helm chart metadata |
| Create | `apps/lineup/values.yaml` | Default values |
| Create | `apps/lineup/templates/deployment.yaml` | Kubernetes Deployment |
| Create | `apps/lineup/templates/service.yaml` | ClusterIP Service |
| Create | `apps/lineup/templates/ingressroute.yaml` | Traefik IngressRoute |

---

### Task 1: Chart.yaml and values.yaml

**Files:**
- Create: `apps/lineup/Chart.yaml`
- Create: `apps/lineup/values.yaml`

- [ ] **Step 1: Create Chart.yaml**

```yaml
apiVersion: v2
name: lineup
description: Lineup web application
type: application
version: 0.1.0
appVersion: "latest"
```

Save to `apps/lineup/Chart.yaml`.

- [ ] **Step 2: Create values.yaml**

```yaml
image:
  repository: ghcr.io/markis/lineup
  tag: "latest"
  pullPolicy: Always

replicas: 1

deployment:
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "256Mi"
      cpu: "200m"

service:
  type: ClusterIP
  port: 80
  targetPort: 80

ingress:
  host: lineup.markis.network
```

Save to `apps/lineup/values.yaml`.

- [ ] **Step 3: Commit**

```bash
git add apps/lineup/Chart.yaml apps/lineup/values.yaml
git commit -m "feat(lineup): add chart metadata and values"
```

---

### Task 2: Deployment template

**Files:**
- Create: `apps/lineup/templates/deployment.yaml`

- [ ] **Step 1: Create deployment.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Chart.Name }}
  labels:
    app: {{ .Chart.Name }}
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/component: web
    app.kubernetes.io/part-of: {{ .Chart.Name }}
  annotations:
    ignore-check.kube-linter.io/no-read-only-root-fs: "nginx requires writable temp directories"
    ignore-check.kube-linter.io/run-as-non-root: "nginx master process runs as root"
spec:
  replicas: {{ .Values.replicas }}
  selector:
    matchLabels:
      app: {{ .Chart.Name }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: {{ .Chart.Name }}
    spec:
      restartPolicy: Always
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 80
          livenessProbe:
            httpGet:
              path: /
              port: 80
              scheme: HTTP
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          readinessProbe:
            httpGet:
              path: /
              port: 80
              scheme: HTTP
            initialDelaySeconds: 5
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          resources:
            requests:
              memory: {{ .Values.deployment.resources.requests.memory }}
              cpu: {{ .Values.deployment.resources.requests.cpu }}
            limits:
              memory: {{ .Values.deployment.resources.limits.memory }}
              cpu: {{ .Values.deployment.resources.limits.cpu | quote }}
```

Save to `apps/lineup/templates/deployment.yaml`.

- [ ] **Step 2: Commit**

```bash
git add apps/lineup/templates/deployment.yaml
git commit -m "feat(lineup): add deployment template"
```

---

### Task 3: Service template

**Files:**
- Create: `apps/lineup/templates/service.yaml`

- [ ] **Step 1: Create service.yaml**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Chart.Name }}
  labels:
    app: {{ .Chart.Name }}
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/component: service
    app.kubernetes.io/part-of: {{ .Chart.Name }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
  selector:
    app: {{ .Chart.Name }}
```

Save to `apps/lineup/templates/service.yaml`.

- [ ] **Step 2: Commit**

```bash
git add apps/lineup/templates/service.yaml
git commit -m "feat(lineup): add service template"
```

---

### Task 4: IngressRoute template

**Files:**
- Create: `apps/lineup/templates/ingressroute.yaml`

- [ ] **Step 1: Create ingressroute.yaml**

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: {{ .Chart.Name }}
  labels:
    app: {{ .Chart.Name }}
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/component: ingress
    app.kubernetes.io/part-of: {{ .Chart.Name }}
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`{{ .Values.ingress.host }}`)
      kind: Rule
      services:
        - name: {{ .Chart.Name }}
          port: {{ .Values.service.port }}
```

Save to `apps/lineup/templates/ingressroute.yaml`.

- [ ] **Step 2: Commit**

```bash
git add apps/lineup/templates/ingressroute.yaml
git commit -m "feat(lineup): add ingressroute template"
```

---

### Task 5: Verify with helm template

**Files:** (none created — verification only)

- [ ] **Step 1: Render templates locally**

```bash
helm template lineup apps/lineup
```

Expected: YAML output for Deployment, Service, and IngressRoute with no errors. Verify:
- Deployment image is `ghcr.io/markis/lineup:latest`
- Service port is `80`
- IngressRoute host is `lineup.markis.network`

- [ ] **Step 2: Confirm ArgoCD will pick it up**

The ApplicationSet in `argocd/apps/` auto-discovers all directories under `apps/`. No further registration is needed — ArgoCD will detect `apps/lineup/` on the next sync.

Verify the ApplicationSet config has not changed:

```bash
cat argocd/apps/values.yaml
```

Expected output includes `basePath: apps` — confirming auto-discovery is active.
