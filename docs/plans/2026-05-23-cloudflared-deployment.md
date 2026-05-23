# Cloudflared Infrastructure Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy cloudflared as an infrastructure Helm chart so Cloudflare Tunnel routes
external traffic through to Traefik and on to cluster apps.

**Architecture:** A local Helm chart at `infrastructure/cloudflared/` is registered in
`argocd/infrastructure/values.yaml` using a `path:` reference. ArgoCD deploys a Deployment
(cloudflared daemon), a ConfigMap (tunnel config), and a OnePasswordItem (credentials secret)
into the `cloudflare` namespace.

**Tech Stack:** Helm v2 chart, Kubernetes, cloudflare/cloudflared:2026.5.0,
1Password Connect (OnePasswordItem CRD), Traefik IngressRoute

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `infrastructure/cloudflared/Chart.yaml` | Helm chart metadata |
| Create | `infrastructure/cloudflared/values.yaml` | Tunnel ID, hostnames, image, resources |
| Create | `infrastructure/cloudflared/templates/configmap.yaml` | cloudflared config.yaml |
| Create | `infrastructure/cloudflared/templates/onepassword-item.yaml` | Credentials secret |
| Create | `infrastructure/cloudflared/templates/deployment.yaml` | cloudflared Deployment |
| Modify | `argocd/infrastructure/values.yaml` | Register cloudflared in ApplicationSet |

---

### Task 1: Chart.yaml and values.yaml

**Files:**

- Create: `infrastructure/cloudflared/Chart.yaml`
- Create: `infrastructure/cloudflared/values.yaml`

- [ ] **Step 1: Create Chart.yaml**

```yaml
apiVersion: v2
name: cloudflared
description: Cloudflare Tunnel daemon routing external traffic to Traefik
type: application
version: 0.1.0
appVersion: "2026.5.0"
```

Save to `infrastructure/cloudflared/Chart.yaml`.

- [ ] **Step 2: Create values.yaml**

```yaml
tunnelId: "b919dff9-5486-4fee-be38-071a3284e121"

image:
  repository: cloudflare/cloudflared
  tag: "2026.5.0"
  pullPolicy: IfNotPresent

ingress:
  - hostname: lineup.markis.network
    service: http://traefik.traefik.svc.cluster.local:80

resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"

secretName: cloudflare-tunnel-credentials
onepassword:
  itemPath: "vaults/k8s-secrets/items/cloudflare-tunnel"
```

Save to `infrastructure/cloudflared/values.yaml`.

- [ ] **Step 3: Commit**

```bash
git add infrastructure/cloudflared/Chart.yaml infrastructure/cloudflared/values.yaml
git commit -m "feat(cloudflared): add chart metadata and values"
```

---

### Task 2: ConfigMap template

**Files:**

- Create: `infrastructure/cloudflared/templates/configmap.yaml`

- [ ] **Step 1: Create configmap.yaml**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Chart.Name }}-config
  labels:
    app: {{ .Chart.Name }}
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/component: config
    app.kubernetes.io/part-of: {{ .Chart.Name }}
data:
  config.yaml: |
    tunnel: {{ .Values.tunnelId }}
    credentials-file: /etc/cloudflared/credentials.json
    ingress:
    {{- range .Values.ingress }}
      - hostname: {{ .hostname }}
        service: {{ .service }}
    {{- end }}
      - service: http_status:404
```

Save to `infrastructure/cloudflared/templates/configmap.yaml`.

- [ ] **Step 2: Commit**

```bash
git add infrastructure/cloudflared/templates/configmap.yaml
git commit -m "feat(cloudflared): add tunnel config configmap"
```

---

### Task 3: OnePasswordItem template

**Files:**

- Create: `infrastructure/cloudflared/templates/onepassword-item.yaml`

- [ ] **Step 1: Create onepassword-item.yaml**

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: {{ .Values.secretName }}
  labels:
    app: {{ .Chart.Name }}
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/component: secrets
    app.kubernetes.io/part-of: {{ .Chart.Name }}
spec:
  itemPath: {{ .Values.onepassword.itemPath | quote }}
```

Save to `infrastructure/cloudflared/templates/onepassword-item.yaml`.

This creates a Secret named `cloudflare-tunnel-credentials` in the `cloudflare` namespace.
The 1Password item at `vaults/k8s-secrets/items/cloudflare-tunnel` has two fields:

- `cert.pem` — Cloudflare origin cert (not mounted in the pod, just present in the Secret)
- `b919dff9-5486-4fee-be38-071a3284e121.json` — tunnel credentials (mounted by Deployment)

- [ ] **Step 2: Commit**

```bash
git add infrastructure/cloudflared/templates/onepassword-item.yaml
git commit -m "feat(cloudflared): add onepassword credentials item"
```

---

### Task 4: Deployment template

**Files:**

- Create: `infrastructure/cloudflared/templates/deployment.yaml`

- [ ] **Step 1: Create deployment.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Chart.Name }}
  labels:
    app: {{ .Chart.Name }}
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/component: tunnel
    app.kubernetes.io/part-of: {{ .Chart.Name }}
  annotations:
    ignore-check.kube-linter.io/no-read-only-root-fs: "cloudflared requires writable dirs"
    ignore-check.kube-linter.io/run-as-non-root: "cloudflared runs as root by default"
spec:
  replicas: 1
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
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
    spec:
      restartPolicy: Always
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          args:
            - tunnel
            - --config=/etc/cloudflared/config.yaml
            - --metrics=0.0.0.0:2000
            - run
          ports:
            - name: metrics
              containerPort: 2000
          readinessProbe:
            httpGet:
              path: /ready
              port: 2000
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 3
            failureThreshold: 3
          resources:
            requests:
              memory: {{ .Values.resources.requests.memory }}
              cpu: {{ .Values.resources.requests.cpu }}
            limits:
              memory: {{ .Values.resources.limits.memory }}
              cpu: {{ .Values.resources.limits.cpu | quote }}
          volumeMounts:
            - name: config
              mountPath: /etc/cloudflared/config.yaml
              subPath: config.yaml
              readOnly: true
            - name: credentials
              mountPath: /etc/cloudflared/credentials.json
              subPath: {{ .Values.tunnelId }}.json
              readOnly: true
      volumes:
        - name: config
          configMap:
            name: {{ .Chart.Name }}-config
        - name: credentials
          secret:
            secretName: {{ .Values.secretName }}
```

Save to `infrastructure/cloudflared/templates/deployment.yaml`.

- [ ] **Step 2: Commit**

```bash
git add infrastructure/cloudflared/templates/deployment.yaml
git commit -m "feat(cloudflared): add deployment template"
```

---

### Task 5: Register in infrastructure ApplicationSet

**Files:**

- Modify: `argocd/infrastructure/values.yaml`

- [ ] **Step 1: Append cloudflared entry to argocd/infrastructure/values.yaml**

Add at the end of the `infra:` list (after the Traefik entry):

```yaml
  # ===========================================================================
  # Cloudflared - Cloudflare Tunnel Daemon
  # ===========================================================================
  # Routes external traffic from Cloudflare into the cluster via Traefik.
  # Tunnel ID: b919dff9-5486-4fee-be38-071a3284e121
  # Credentials stored in 1Password: vaults/k8s-secrets/items/cloudflare-tunnel
  # ===========================================================================
  - name: cloudflared
    namespace: cloudflare
    repoURL: https://github.com/markis/cluster-config.git
    path: infrastructure/cloudflared
    targetRevision: main
```

- [ ] **Step 2: Commit**

```bash
git add argocd/infrastructure/values.yaml
git commit -m "feat(cloudflared): register in infrastructure ApplicationSet"
```

---

### Task 6: Verify and push

**Files:** (none created — verification and push only)

- [ ] **Step 1: Check helm template renders cleanly**

```bash
helm template cloudflared infrastructure/cloudflared
```

Expected: YAML output for ConfigMap, OnePasswordItem, and Deployment with no errors.
Verify:

- ConfigMap `data.config.yaml` contains `tunnel: b919dff9-5486-4fee-be38-071a3284e121`
- ConfigMap ingress list includes `lineup.markis.network` and catch-all `http_status:404`
- Deployment image is `cloudflare/cloudflared:2026.5.0`
- Deployment `credentials` volume mounts
  `subPath: b919dff9-5486-4fee-be38-071a3284e121.json`

- [ ] **Step 2: Push to origin**

```bash
git push origin main
```

ArgoCD will detect the new `cloudflared` Application in `argocd/infrastructure/values.yaml`
on its next sync and deploy all resources into the `cloudflare` namespace.

- [ ] **Step 3: Confirm ArgoCD syncs**

```bash
kubectl get applications -n argocd | grep cloudflared
```

Expected: `infra.cloudflared` with `Synced` and `Healthy` status (may take 1-2 minutes).

```bash
kubectl get pods -n cloudflare
```

Expected: `cloudflared-<hash>` pod in `Running` state.
