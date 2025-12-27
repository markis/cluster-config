# Cluster Config - ArgoCD App of Apps Pattern

ArgoCD GitOps repository using the App of Apps pattern for Kubernetes cluster management. Includes infrastructure components (ArgoCD, Traefik, cert-manager, 1Password Connect). Supports automated sync, self-healing, and pruning.

## Repository Structure

```
.
├── bootstrap/                    # Bootstrap manifests (apply manually once)
│   └── apps.yaml                # Root Application that manages all other apps
├── apps/                         # Application manifests (watched by app-of-apps)
│   ├── infrastructure.yaml      # Parent app for infrastructure components
│   └── infrastructure/          # Infrastructure component Applications
│       ├── argocd.yaml          # ArgoCD (self-managed)
│       ├── traefik.yaml         # Traefik Ingress Controller
│       ├── cert-manager.yaml    # cert-manager for TLS
│       └── 1password-connect.yaml # 1Password secrets management
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
                               ▼
                    ┌─────────────────────┐
                    │   infrastructure    │
                    │   (apps/)           │
                    └──────────┬──────────┘
                               │
         ┌─────────┬───────────┼───────────┬─────────┐
         │         │           │           │         │
         ▼         ▼           ▼           ▼         ▼
      ┌──────┐ ┌───────┐ ┌──────────┐ ┌──────────────┐
      │argocd│ │traefik│ │cert-mgr  │ │1password-conn│
      └──────┘ └───────┘ └──────────┘ └──────────────┘
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

## Adding New Applications

### Using Helm (External Chart)

Create a new Application manifest in `apps/`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://charts.example.com
    chart: my-chart
    targetRevision: 1.0.0
    helm:
      releaseName: my-app
      values: |
        replicaCount: 2
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Using Helm (Git Repository with Values Overlays)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/markis/cluster-config.git
    targetRevision: main
    path: apps/my-app/base
    helm:
      valueFiles:
        - values.yaml
        - ../overlays/prod/values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Using Kustomize

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/markis/cluster-config.git
    targetRevision: main
    path: apps/my-app/overlays/prod
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app-prod
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
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
