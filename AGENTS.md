# AGENTS.md - Developer Guide for AI Coding Agents

This repository is a Kubernetes GitOps cluster configuration using ArgoCD, Helm, and the App of Apps pattern. This guide provides essential information for AI coding agents working in this repository.

## Build, Lint & Test Commands

### Agent Hooks Setup
This repository includes agent hooks to ensure code quality before commits. Install them once after cloning:

```bash
# Install agent hooks (creates symlinks from .agents/hooks/ to .git/hooks/)
.agents/hooks/install.sh
```

The pre-commit hook automatically runs:
- **yamllint**: Validates YAML formatting and syntax
- **markdownlint**: Validates Markdown documentation consistency
- **editorconfig-checker**: Validates file formatting (.editorconfig compliance)
- **shellcheck**: Lints shell scripts for common issues
- **shfmt**: Formats shell scripts (default style: tabs, posix)
- **helm lint --strict**: Validates all Helm chart syntax
- **kubeconform**: Validates rendered Kubernetes manifests
- **kube-linter**: Security linting for Kubernetes manifests
- **trivy**: Security vulnerability scanning for Kubernetes configs

**For AI agents**: Before creating commits, always run `.agents/hooks/pre-commit` to validate changes. If the hook fails, fix the issues before committing.

To skip hooks temporarily (not recommended):
```bash
git commit --no-verify
```

### Linter Configuration Files
- `.yamllint` - YAML formatting and syntax rules
- `.markdownlint.yaml` - Markdown documentation style rules
- `.kube-linter.yaml` - Kubernetes security checks configuration
- `trivy.yaml` - Security vulnerability scanning configuration
- `.trivyignore` - Accepted/ignored vulnerabilities
- `.editorconfig` - File formatting rules (indentation, line endings)

### Helm Linting
```bash
# Lint all charts
find . -name Chart.yaml -exec dirname {} \; | xargs -I {} helm lint {} --strict

# Lint a single chart
helm lint apps/mqtt --strict
```

### Helm Templating & Validation
```bash
# Template a single chart (check for errors)
helm template apps/mqtt --debug

# Template and validate with kubeconform
helm template apps/mqtt | kubeconform -strict -kubernetes-version 1.25.0 -summary -ignore-missing-schemas

# Test rendering with different values
helm template apps/mqtt --set replicaCount=1 --debug
```

### Security & Quality Scanning
```bash
# Run kube-linter security checks
helm template apps/mqtt | kube-linter lint --config .kube-linter.yaml -

# Run trivy security vulnerability scan
helm template apps/mqtt | trivy config --config trivy.yaml --severity CRITICAL,HIGH -

# Run yamllint on all YAML files
yamllint .

# Run markdownlint on all Markdown files
markdownlint '**/*.md' --ignore node_modules
```

### CI/CD Pipeline
The GitHub Actions workflow (`.github/workflows/lint-and-security.yml`) automatically:
1. Runs yamllint on all YAML files
2. Runs markdownlint on all Markdown files
3. Discovers all Helm charts (by finding `Chart.yaml` files)
4. Runs `helm lint --strict` on each chart
5. Templates each chart with `helm template --debug`
6. Validates manifests with `kubeconform`
7. Runs `kube-linter` security checks on each chart
8. Runs `trivy` security vulnerability scans on each chart

### ArgoCD Commands
```bash
# List all applications
kubectl get applications -n argocd

# Get application status
kubectl describe application <app-name> -n argocd

# Run argocd CLI commands from within ArgoCD pods
# (argocd CLI is not installed locally - use kubectl exec)
kubectl exec -n argocd deployment/argocd-server -- argocd app list
kubectl exec -n argocd deployment/argocd-server -- argocd app get <app-name>
kubectl exec -n argocd deployment/argocd-server -- argocd app sync <app-name> --force

# View ArgoCD logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller
```

## Code Style Guidelines

### File Format (.editorconfig)
- **Encoding**: UTF-8
- **Line endings**: LF (Unix-style)
- **Indentation**: 2 spaces (YAML, JSON, shell scripts)
- **Final newline**: Required
- **Trailing whitespace**: Trimmed (except Markdown)
- **Makefiles**: Use tabs with size 4

### YAML Style
```yaml
# Indentation: 2 spaces
# No tabs allowed
# Keys and values separated by ": " (colon-space)
# Lists use "- " (dash-space) indentation
# Multi-line strings use "|" or ">" as appropriate

apiVersion: apps/v1
kind: Deployment
metadata:
  name: example
  labels:
    app: example
spec:
  replicas: 1
  selector:
    matchLabels:
      app: example
```

### Helm Templates
```yaml
# Use .Chart.Name for resource names (not hardcoded)
name: {{ .Chart.Name }}

# Use .Values for all configurable parameters
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"

# Use consistent label patterns
labels:
  app: {{ .Chart.Name }}
  app.kubernetes.io/name: {{ .Chart.Name }}
  app.kubernetes.io/component: <component-type>
  app.kubernetes.io/part-of: {{ .Chart.Name }}

# Use toYaml for nested structures
resources:
  {{- toYaml .Values.resources | nindent 12 }}
```

### Naming Conventions
- **Chart names**: Lowercase with hyphens (`mqtt`, `zwave-js`, `budget-importer`)
- **Kubernetes resources**: Use `{{ .Chart.Name }}` for consistency
- **ConfigMaps/Secrets**: Suffix with `-config` or `-secrets` (e.g., `mqtt-config`)
- **Services**: Use `{{ .Chart.Name }}` for primary service
- **Headless services**: Suffix with `-headless`
- **Environment variables**: UPPERCASE_WITH_UNDERSCORES

### Directory Structure
```
apps/<app-name>/
├── Chart.yaml              # Required: Helm chart metadata
├── values.yaml             # Required: Default values
├── templates/              # Required: Kubernetes manifests
│   ├── deployment.yaml     # or statefulset.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   ├── ingress.yaml        # or ingressroute.yaml (Traefik CRD)
│   └── onepassword-item.yaml  # 1Password secret integration
├── scripts/                # Optional: Backup/restore scripts
│   ├── backup.sh
│   ├── restore.sh
│   └── init-config.sh
└── README.md               # Optional: App-specific documentation
```

### Shell Script Style
```bash
#!/bin/sh
set -e  # Exit on error

# Use double quotes for variables
echo "Creating backup: ${BACKUP_NAME}"

# Check for required variables
: "${REQUIRED_VAR:?Variable REQUIRED_VAR is not set}"

# Use descriptive variable names (UPPERCASE for environment)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="app-${TIMESTAMP}.tar.gz"
```

### Values.yaml Structure
```yaml
# Image configuration
image:
  repository: ghcr.io/user/app
  tag: "1.0.0"
  pullPolicy: IfNotPresent

# Resource limits (always specify)
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"
  limits:
    memory: "256Mi"
    cpu: "200m"

# Service configuration
service:
  type: ClusterIP  # or LoadBalancer
  port: 8080

# Secret management (1Password)
secretName: app-secrets
onepassword:
  itemPath: "vaults/k8s-secrets/items/app-name"

# Application config
config:
  key: value
```

## Error Handling & Validation

### Required Health Checks
All deployments/statefulsets MUST include:
```yaml
livenessProbe:
  # TCP or HTTP based on application
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 1-5
  failureThreshold: 3

readinessProbe:
  # Should match service readiness
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 1-5

startupProbe:  # Optional for slow-starting apps
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 30
```

### Secret Management
- **Never hardcode secrets** in YAML files
- Use 1Password Connect for secret injection
- Reference secrets via `secretKeyRef`:
```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ .Values.secretName }}
        key: db-password
```

## Git Workflow

### Commit Messages
- Keep concise (1-2 lines preferred)
- Focus on "why" rather than "what"
- Examples from repo history:
  - "Add mqtt helm chart with EMQX clustering"
  - "Update traefik ingress to match external hostname"
  - "Fix backup script SSH key permissions"

### Branch Strategy
- Main branch: `main`
- Direct commits allowed (no PR requirement visible)
- ArgoCD syncs from `main` branch

## ArgoCD Integration

### Auto-Discovery
Applications in `apps/` are automatically discovered via ApplicationSet. No manual registration needed.

### Sync Policy
All applications use:
- **Automated sync** enabled
- **prune: true** - removes deleted resources
- **selfHeal: true** - reverts manual changes
- **CreateNamespace=true** - auto-creates namespaces

### Adding New Apps
1. Create Helm chart in `apps/<name>/`
2. Include `Chart.yaml` and `values.yaml`
3. Add templates in `templates/` directory
4. Commit and push - ArgoCD auto-deploys

## Special Considerations

### ConfigMaps with External Files
For ConfigMaps containing config files, use external files and load them into the ConfigMap rather than embedding content directly:
```yaml
# templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Chart.Name }}-config
data:
  {{- (.Files.Glob "config/*").AsConfig | nindent 2 }}
```

Store config files in a `config/` directory within the chart:
```
apps/<app-name>/
├── config/
│   ├── app.conf
│   └── settings.ini
└── templates/
    └── configmap.yaml
```

This keeps templates clean and makes config files easier to edit and maintain.

### 1Password Integration
All apps use 1Password Connect for secrets:
```yaml
# templates/onepassword-item.yaml
apiVersion: onepassword.com/v1
kind: OnePasswordItem
metadata:
  name: {{ .Values.secretName }}
spec:
  itemPath: {{ .Values.onepassword.itemPath | quote }}
```

### Multi-Container Pods
When using sidecars (e.g., MQTT with Redis):
- Name containers clearly
- Separate resource limits per container
- Use lifecycle hooks for initialization

### StatefulSets
For stateful applications (databases, message brokers):
- Use `serviceName` field for headless service
- Include proper clustering configuration
- Implement backup/restore jobs

### Ingress Configuration
Use external hostnames matching OPNsense Caddy/relayd setup:
```yaml
spec:
  ingressClassName: traefik
  rules:
    - host: app.markis.network  # External FQDN
```

## Testing Checklist

Before committing Helm chart changes:
- [ ] Run `helm lint <chart> --strict`
- [ ] Run `helm template <chart> --debug` (no errors)
- [ ] Validate with `kubeconform`
- [ ] Check resource limits are specified
- [ ] Verify health probes are present
- [ ] Ensure secrets use 1Password (not hardcoded)
- [ ] Test with different values if applicable
