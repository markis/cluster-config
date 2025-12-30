# Cluster Config - ArgoCD App of Apps Pattern

ArgoCD GitOps repository using the App of Apps pattern for Kubernetes cluster management. Uses ApplicationSets for automatic app discovery. Includes infrastructure components (ArgoCD, Traefik, cert-manager, 1Password Connect) and application workloads deployed as Helm charts.

## Repository Structure

```
.
├── bootstrap/                    # Bootstrap manifests (apply manually once)
│   └── apps.yaml                # Root Application that manages all other apps
├── argocd/                       # ArgoCD ApplicationSet configurations
│   ├── apps.yaml                # Parent app for application workloads
│   ├── infrastructure.yaml      # Parent app for infrastructure components
│   ├── apps/                    # ApplicationSet for apps/ directory
│   │   └── templates/
│   │       └── applications.yaml
│   └── infrastructure/          # ApplicationSet for infrastructure
│       └── templates/
│           └── applications.yaml
├── apps/                         # Application Helm charts (auto-discovered)
│   ├── budget-importer/         # Scheduled budget data importer
│   ├── dark-detector/           # Dark mode detection service
│   ├── dynasty/                 # Fantasy football tracker
│   ├── hass-dashboard/          # Home Assistant dashboard
│   └── mqtt/                    # MQTT broker (Mosquitto)
├── .gitignore                   # Git ignore patterns
├── .editorconfig                # Editor configuration
└── README.md                    # This file
```

## Prerequisites

- Kubernetes cluster (1.25+)
- kubectl configured to access your cluster
- ArgoCD installed (for initial bootstrap)

## Bootstrap Process

### Step 1: Install ArgoCD (if not already installed)

```bash
# Create the argocd namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
```

### Step 2: Apply the Apps Bootstrap

```bash
# Apply the root Application
kubectl apply -f bootstrap/apps.yaml
```

This single command bootstraps the entire GitOps workflow:

1. ArgoCD creates the `cluster` Application
2. `cluster` watches the `apps/` directory
3. ArgoCD discovers and creates all Application manifests in `apps/`
4. Each Application deploys its respective workload

### Step 3: Access ArgoCD UI

```bash
# Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Port forward to access the UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080 and login with:
- Username: `admin`
- Password: (from the command above)

## Architecture

### App of Apps Pattern

```
                         ┌─────────────────────┐
                         │      cluster        │
                         │   (bootstrap/)      │
                         └──────────┬──────────┘
                                    │
                 ┌──────────────────┴──────────────────┐
                 │                                     │
                 ▼                                     ▼
      ┌─────────────────────┐             ┌─────────────────────┐
      │   infrastructure    │             │       apps          │
      │   (argocd/)         │             │   (argocd/)         │
      └──────────┬──────────┘             └──────────┬──────────┘
                 │                                    │
    ┌────────────┼────────────┐          ┌───────────┼───────────┐
    │      │     │     │      │          │     │     │     │     │
    ▼      ▼     ▼     ▼      ▼          ▼     ▼     ▼     ▼     ▼
 argocd traefik cert  1pass  ...      budget dark  dynasty hass mqtt
                -mgr  -conn           -import -det        -dash
```

### Sync Configuration

All Applications use automated sync with:
- **prune**: Removes resources deleted from Git
- **selfHeal**: Reverts manual cluster changes
- **CreateNamespace=true**: Auto-creates target namespaces

## Infrastructure Components

| Component | Description | Chart Source |
|-----------|-------------|--------------|
| ArgoCD | GitOps CD platform (self-managed) | argoproj/argo-helm |
| Traefik | Ingress Controller | traefik/traefik |
| cert-manager | TLS certificate management | jetstack/cert-manager |
| 1Password Connect | Secrets management | 1password/connect |

## Application Workloads

All applications are Helm charts in the `apps/` directory, automatically discovered and deployed by the ApplicationSet.

| Application | Description | Components |
|-------------|-------------|------------|
| budget-importer | Scheduled budget data importer | CronJob, 1Password secrets |
| dark-detector | Dark mode detection service | Deployment, ConfigMap, 1Password secrets |
| dynasty | Fantasy football tracker | Deployment, CronJob, Service (LoadBalancer), 1Password secrets |
| hass-dashboard | Home Assistant dashboard generator | Deployment (generator + nginx), Service, ConfigMap, 1Password secrets |
| mqtt | MQTT broker (Mosquitto) | StatefulSet, Services, ConfigMap, RBAC, 1Password secrets |

## Adding New Applications

### Adding an Application (Helm Chart in apps/)

The ApplicationSet automatically discovers Helm charts in `apps/`. Simply create a new directory:

```
apps/my-app/
├── Chart.yaml
├── values.yaml
└── templates/
    ├── deployment.yaml
    ├── service.yaml
    └── onepassword-item.yaml  # If using 1Password secrets
```

Example `Chart.yaml`:

```yaml
apiVersion: v2
name: my-app
description: My application description
type: application
version: 0.1.0
appVersion: "1.0.0"
```

Example `values.yaml`:

```yaml
image:
  repository: ghcr.io/username/my-app
  tag: "1.0.0"
  pullPolicy: IfNotPresent

resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"

service:
  type: ClusterIP
  port: 8080

secretName: my-app-secrets
```

### Adding Infrastructure Components

Add a new entry to `argocd/infrastructure/values.yaml`:

```yaml
infra:
  - name: my-component
    namespace: my-namespace
    repoURL: https://charts.example.com
    chart: my-chart
    targetRevision: 1.0.0
    values: |
      replicaCount: 2
```

### Using 1Password for Secrets

Create a `onepassword-item.yaml` template:

```yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: {{ .Values.secretName }}
spec:
  itemPath: "vaults/k8s-secrets/items/my-app"
```

Then reference the secret in your deployment:

```yaml
env:
  - name: MY_SECRET
    valueFrom:
      secretKeyRef:
        name: {{ .Values.secretName }}
        key: my-secret-key
```

## Configuration

### Sync Options Reference

| Option | Description |
|--------|-------------|
| `CreateNamespace=true` | Create namespace if missing |
| `PruneLast=true` | Prune after other syncs complete |
| `ApplyOutOfSyncOnly=true` | Only sync out-of-sync resources |
| `ServerSideApply=true` | Use server-side apply (for CRDs) |

### Automated Sync Settings

```yaml
syncPolicy:
  automated:
    prune: true      # Delete removed resources
    selfHeal: true   # Revert manual changes
    allowEmpty: false # Don't sync empty apps
```

## Troubleshooting

### Check Application Status

```bash
# List all applications
kubectl get applications -n argocd

# Get detailed status
kubectl describe application <app-name> -n argocd

# View sync status
argocd app get <app-name>
```

### Force Sync

```bash
argocd app sync <app-name> --force
```

### View Logs

```bash
# ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller

# ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server
```

## Exposing Services via OPNsense (Caddy + relayd)

Services in the k3s cluster are exposed externally through OPNsense using Caddy (reverse proxy with TLS) and relayd (load balancing). This provides a single entry point with automatic TLS certificates.

### Architecture

```
External:  https://myservice.markis.network
              ↓
           Unbound DNS → 10.0.0.1 (OPNsense)
              ↓
           Caddy (TLS termination, header rewrite)
              ↓
Internal:  myservice.k3s.lan:8080
              ↓
           Unbound DNS → 10.0.0.16 (relayd VIP)
              ↓
           relayd (round-robin load balancing)
              ↓
           10.0.0.10-13:80 (k3s nodes)
              ↓
           Traefik Ingress (Host: myservice.k3s.lan)
              ↓
           Service in cluster
```

### Adding a New Service

When adding a new service (e.g., `argocd`), configure the following in OPNsense:

#### 1. Unbound DNS - External Override

**Services → Unbound DNS → Host Overrides → Add**

| Setting | Value |
|---------|-------|
| Host | `argocd` |
| Domain | `markis.network` |
| Type | A |
| IP | `10.0.0.1` |
| Description | `ArgoCD - route to Caddy` |

This routes external hostname to Caddy on OPNsense.

#### 2. Unbound DNS - Internal Override

**Services → Unbound DNS → Host Overrides → Add**

| Setting | Value |
|---------|-------|
| Host | `argocd` |
| Domain | `k3s.lan` |
| Type | A |
| IP | `10.0.0.16` |
| Description | `ArgoCD - route to relayd VIP` |

This routes internal hostname to the relayd VIP.

#### 3. Caddy - Domain

**Services → Caddy Web Server → Reverse Proxy → Domains → Add**

| Setting | Value |
|---------|-------|
| Domain | `argocd.markis.network` |
| Description | `ArgoCD` |

#### 4. Caddy - Handler

**Services → Caddy Web Server → Reverse Proxy → Handlers → Add**

| Setting | Value |
|---------|-------|
| Domain | `argocd.markis.network` |
| Upstream Domain | `argocd.k3s.lan` |
| Upstream Port | `8080` |

#### 5. Caddy - Header (Rewrite Host)

**Services → Caddy Web Server → Reverse Proxy → Headers → Add**

| Setting | Value |
|---------|-------|
| Handler | (select the argocd handler) |
| Header Type | `Host` |
| Header Value | `^(.+)\.markis\.network$` |
| Header Replace | `$1.k3s.lan` |

This regex rewrites `argocd.markis.network` → `argocd.k3s.lan` so Traefik matches the correct Ingress.

#### 6. Traefik Ingress (in cluster)

Add an Ingress resource for your service:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd
  namespace: argocd
spec:
  ingressClassName: traefik
  rules:
    - host: argocd.k3s.lan
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
```

#### 7. Application Configuration (if needed)

If your application validates the Origin header (like Grafana), update its `root_url` or equivalent setting to use the external URL:

```yaml
# Example for Grafana
grafana.ini:
  server:
    root_url: https://argocd.markis.network
```

### Existing Infrastructure

The following are already configured and shared by all services:

| Component | Configuration |
|-----------|---------------|
| **relayd VIP** | `10.0.0.16` on LAN (ax1) interface |
| **relayd Virtual Server** | `k3s_http` - listens on `:8080`, forwards to `pi_cluster:80` |
| **Firewall Rule** | Allow TCP 8080 to `10.0.0.16` |
| **Caddy Header Regex** | `^(.+)\.markis\.network$` → `$1.k3s.lan` (reusable) |

### Quick Checklist

For each new service, add:

- [ ] Unbound: `service.markis.network` → `10.0.0.1`
- [ ] Unbound: `service.k3s.lan` → `10.0.0.16`
- [ ] Caddy Domain: `service.markis.network`
- [ ] Caddy Handler: upstream `service.k3s.lan:8080`
- [ ] Caddy Header: reuse the regex pattern (or create per-handler)
- [ ] Traefik Ingress: `host: service.k3s.lan`
- [ ] App config: update `root_url` if needed for CORS

## Security Considerations

1. **RBAC**: Create custom ArgoCD projects with limited permissions
2. **Secrets**: Use external secrets management (1Password, Vault)
3. **Network Policies**: Restrict ArgoCD network access
4. **Audit**: Enable ArgoCD audit logging
5. **Git**: Use signed commits and protected branches

## License

MIT
