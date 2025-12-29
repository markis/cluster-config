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

## Security Considerations

1. **RBAC**: Create custom ArgoCD projects with limited permissions
2. **Secrets**: Use external secrets management (1Password, Vault)
3. **Network Policies**: Restrict ArgoCD network access
4. **Audit**: Enable ArgoCD audit logging
5. **Git**: Use signed commits and protected branches

## License

MIT
