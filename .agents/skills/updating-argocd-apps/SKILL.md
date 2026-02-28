---
name: updating-argocd-apps
description: Use when updating Kubernetes applications managed by ArgoCD/Helm in GitOps repos - handles version checks, file updates, conventional commits, and sync verification
---

# Updating ArgoCD Applications

## Overview

Complete workflow for updating container images in Helm-managed Kubernetes applications with ArgoCD GitOps sync. Ensures proper version discovery, file updates, commit conventions, and deployment verification.

## When to Use

Use this skill when:
- Updating container image versions in Helm charts
- User requests "update X to latest" for ArgoCD-managed apps
- Making version changes that need ArgoCD sync
- Working with GitOps repositories with apps/ structure

Don't use for:
- Manual kubectl deployments (not GitOps)
- Non-containerized updates
- Infrastructure-as-code outside Kubernetes

## Quick Reference

| Step | Command Pattern | Purpose |
|------|----------------|---------|
| 0. Pre-flight | `kubectl get applications -n argocd \| grep app-name` | Verify app exists, note exact name |
| 1. Find latest | `skopeo list-tags docker://registry/image \| grep -E '^[0-9]' \| sort -V \| tail -1` | Get semantic versions only |
| 2. Update files | Edit `values.yaml` tag + `Chart.yaml` appVersion | Keep versions in sync |
| 3. Commit | `git commit -m "chore: update app-name to vX.Y.Z"` | Conventional commit format |
| 4. Sync | `kubectl -n argocd patch application app.name --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'` | Force ArgoCD refresh |
| 5. Verify | `kubectl get application app.name -n argocd` | Check Synced/Healthy status |

## Complete Workflow

**IMPORTANT: Before starting, ask the user for:**
1. SSH username for cluster access
2. Cluster IP address or hostname

These will be needed for step 4 (Trigger ArgoCD Sync).

### 0. Pre-flight Checks (ALWAYS DO THIS FIRST)

**Before making any changes, verify the application exists and check current state:**

```bash
# 1. List all applications to confirm exact name (note the 'app.' prefix)
kubectl get applications -n argocd | grep <app-name>

# Example output:
# app.my-app   Synced        Healthy

# 2. Check current deployed version
kubectl get application app.<app-name> -n argocd -o yaml | grep -A5 spec: | grep targetRevision

# 3. Find actual pod namespace (often 'default', not app name)
kubectl get pods -A | grep <app-name>

# 4. Check current image version in pod
kubectl get pods -A | grep <app-name> | awk '{print $1, $2}' | while read ns pod; do
  kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[*].image}'
done
```

**Why pre-flight?** Prevents common mistakes:
- Using wrong app name (missing `app.` prefix)
- Assuming wrong namespace
- Updating to version already deployed
- Breaking a working deployment

### 1. Discover Latest Version

```bash
# Use skopeo for registry queries (works without authentication for public registries)
skopeo list-tags docker://ghcr.io/user/app-name

# Filter to semantic versions only (exclude sha- tags)
skopeo list-tags docker://ghcr.io/user/app-name | jq -r '.Tags[]' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
```

**Common registries:**
- GitHub: `ghcr.io/owner/repo`
- Docker Hub: `docker.io/library/image` or `docker.io/user/image`
- Quay: `quay.io/org/image`

### 2. Update Helm Chart Files

**MUST update BOTH files to keep versions synchronized:**

```yaml
# apps/app-name/values.yaml
image:
  repository: ghcr.io/user/app-name
  tag: "2.4.4"  # ← Update this
  
# apps/app-name/Chart.yaml
apiVersion: v2
name: app-name
appVersion: "2.4.4"  # ← Update this too
```

**Why both?** 
- `values.yaml` controls actual deployment
- `Chart.yaml` tracks application version for ArgoCD UI
- Mismatch causes confusion in monitoring/debugging

### 3. Commit with Conventional Format

```bash
# Stage both files
git add apps/app-name/Chart.yaml apps/app-name/values.yaml

# Conventional commit format: type: description
git commit -m "chore: update app-name to v2.4.4"

# Push to trigger ArgoCD
git push
```

**Commit type guide:**
- `chore:` - version bumps, dependency updates
- `feat:` - new functionality
- `fix:` - bug fixes
- `refactor:` - restructuring without behavior change

### 4. Trigger ArgoCD Sync

ArgoCD polls git every 3 minutes by default. Force immediate sync:

**Before proceeding, ask the user for:**
- SSH username for cluster access
- Cluster IP address or hostname

```bash
# SSH to cluster
ssh <username>@<cluster-ip>

# Patch application to trigger hard refresh
kubectl -n argocd patch application app.<app-name> \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

**Application naming:** ArgoCD apps use `app.` prefix (e.g., `app.my-app`). List all:
```bash
kubectl get applications -n argocd
```

### 5. Verify Deployment

```bash
# Check ArgoCD application status
kubectl get application app.<app-name> -n argocd

# Expected output:
# NAME              SYNC STATUS   HEALTH STATUS
# app.my-app   Synced        Healthy

# Watch pod rollout
kubectl get pods -A | grep <app-name>

# Check for new pod with recent timestamp
# Old pod terminates after new pod is healthy (rolling update)
```

**Status meanings:**
- `Synced` + `Healthy` = Deployment successful
- `Synced` + `Progressing` = Rolling update in progress (wait 10-30s)
- `OutOfSync` = Git changes not yet applied (wait or re-trigger)
- `Degraded` = Deployment failed (check pod logs)

## Complete Example

```bash
# 1. Check current version
cat apps/my-app/values.yaml | grep tag:
# Output: tag: "2.4.3"

# 2. Find latest version
skopeo list-tags docker://ghcr.io/org/my-app | \
  jq -r '.Tags[]' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1
# Output: 2.4.4

# 3. Update both files (use Edit tool)
# values.yaml: tag: "2.4.3" → "2.4.4"
# Chart.yaml: appVersion: "2.4.3" → "2.4.4"

# 4. Commit and push
git add apps/my-app/{Chart.yaml,values.yaml}
git commit -m "chore: update my-app to v2.4.4"
git push

# 5. SSH and trigger sync (ask user for SSH username and cluster IP first)
ssh <username>@<cluster-ip>
kubectl -n argocd patch application app.my-app \
  --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# 6. Verify
kubectl get application app.my-app -n argocd
# Wait for "Synced" + "Healthy"

kubectl get pods -A | grep my-app
# Verify new pod is Running
```

## Common Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| Only updating values.yaml | Chart.yaml shows old version in ArgoCD UI | Update both files |
| Using `app-name` instead of `app.app-name` | "application not found" error | Do pre-flight check to get exact name |
| Trying to use argocd CLI | "server address unspecified" error | Use kubectl patch (works without CLI setup) |
| Not waiting for rollout | Checking pods immediately shows old version | Wait 10-30s for rolling update |
| Wrong namespace assumption | Can't find pods | Check all namespaces: `kubectl get pods -A \| grep app` |
| Skipping pre-flight checks | Update wrong app or version already deployed | Always run step 0 first |
| Forgetting to push | ArgoCD never syncs | Verify commit appears in `git log` on remote |
| SSH authentication issues | Permission denied | Verify SSH key and correct username |
| Including sha- tags in version list | Gets wrong "latest" version | Filter with `grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'` |

## Troubleshooting

**Application won't sync:**
```bash
# Check ArgoCD application details
kubectl describe application app.<name> -n argocd

# View ArgoCD controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50
```

**Pod stuck in ImagePullBackOff:**
```bash
# Describe pod to see image pull errors
kubectl describe pod <pod-name> -n <namespace>

# Verify image exists
skopeo inspect docker://<registry>/<image>:<tag>
```

**Wrong application namespace:**
```bash
# ArgoCD applications live in 'argocd' namespace
# But actual pods deploy to app-specific namespaces (often 'default')
kubectl get pods -A | grep <app-name>  # Find actual namespace
```

## ArgoCD Sync Behavior

**Auto-sync:** Most apps in App of Apps pattern have:
- `automated: prune: true, selfHeal: true`
- Polls git every 3 minutes
- Manual sync for immediate updates

**Sync waves:** Apps may have dependencies via sync waves. If app doesn't update:
```bash
# Check sync annotations
kubectl get application app.<name> -n argocd -o yaml | grep sync
```

## Integration with AGENTS.md

This workflow follows the repository's `AGENTS.md` conventions:
- Conventional commit format (chore: update)
- ArgoCD sync via kubectl patch
- Verification before declaring success
- App of Apps auto-discovery pattern

For project-specific details, always check:
- `AGENTS.md` - Build/test commands, conventions
- `.editorconfig` - File formatting rules
- `apps/*/README.md` - App-specific notes
