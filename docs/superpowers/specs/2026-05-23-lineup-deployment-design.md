# Lineup Deployment Design

**Date:** 2026-05-23

## Overview

Add a Helm chart deployment for `ghcr.io/markis/lineup:latest` — a Node.js + nginx web application exposed at `lineup.markis.network`. Follows the existing app-of-apps pattern; ArgoCD auto-discovers and deploys any chart added under `apps/`.

## Files

```
apps/lineup/
  Chart.yaml
  values.yaml
  templates/
    deployment.yaml
    service.yaml
    ingressroute.yaml
```

## Chart.yaml

Standard Helm v2 application chart, name `lineup`, version `0.1.0`.

## values.yaml

| Key | Value |
|-----|-------|
| `image.repository` | `ghcr.io/markis/lineup` |
| `image.tag` | `latest` |
| `image.pullPolicy` | `Always` (required for `latest` tag) |
| `replicas` | `1` |
| `service.type` | `ClusterIP` |
| `service.port` | `80` |
| `service.targetPort` | `80` |
| `ingress.host` | `lineup.markis.network` |
| `deployment.resources.requests` | `memory: 128Mi, cpu: 100m` |
| `deployment.resources.limits` | `memory: 256Mi, cpu: 200m` |

## templates/deployment.yaml

Single-container Deployment:
- Image: `{{ .Values.image.repository }}:{{ .Values.image.tag }}`
- `imagePullPolicy: Always`
- Port 80 (nginx)
- HTTP liveness + readiness probes on `GET /` port 80
- `kube-linter` annotation suppressing `no-read-only-root-fs` and `run-as-non-root` (nginx master process requires root and writable dirs)
- RollingUpdate strategy (`maxSurge: 1, maxUnavailable: 0`)
- Resource requests/limits from values

## templates/service.yaml

ClusterIP Service, port 80 → targetPort 80. Matches the pattern used by all other apps.

## templates/ingressroute.yaml

Traefik `IngressRoute` on entryPoint `web`, matching `Host("lineup.markis.network")`, routing to the lineup Service on port 80. Identical structure to dynasty's IngressRoute.

## What is NOT included

- No `onepassword-item.yaml` — no secrets required
- No `configmap.yaml` — no external config files needed
- No `cronjob.yaml` — lineup is a long-running service, not a batch job
- No `enabled` flag — unlike hermes-agent, lineup should deploy unconditionally
