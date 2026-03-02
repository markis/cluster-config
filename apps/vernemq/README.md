# VerneMQ MQTT Broker

VerneMQ is a high-performance, distributed MQTT message broker designed for IoT and M2M scenarios.

## Chart Information

- **Chart Name**: vernemq
- **App Version**: 2.0.1
- **Deployment**: StatefulSet with 3 replicas (HA cluster)
- **Namespace**: default
- **Service**: LoadBalancer on port 1883 (MQTT)

## Architecture

```
External Clients (10.0.0.1:1883)
         ↓
    relayd (TCP relay)
         ↓
    LoadBalancer Service (vernemq)
         ↓
    ┌─────────────────────────────┐
    │   VerneMQ Cluster (3 pods)  │
    │  vernemq-0, vernemq-1, -2   │
    │  Erlang clustering via DNS  │
    └─────────────────────────────┘
         ↓
    Headless Service (vernemq-headless)
    - Pod discovery
    - Erlang cluster communication
```

## Features

- **Native Kubernetes Clustering**: Auto-discovers pods via headless Service
- **File-based Authentication**: Uses bcrypt password hashes (vmq.passwd)
- **ACL Support**: Topic-based access control (vmq.acl)
- **Persistent Storage**: 1Gi PVC per pod for session/message persistence
- **Health Checks**: Liveness, readiness, and startup probes
- **ARM64 Support**: Optimized for Raspberry Pi k3s clusters
- **Prometheus Metrics**: Exposed on port 8888

## Configuration

### Values (values.yaml)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of VerneMQ pods | `3` |
| `image.repository` | VerneMQ Docker image | `vernemq/vernemq` |
| `image.tag` | Image tag | `2.0.1-alpine` |
| `resources.requests.memory` | Memory request per pod | `256Mi` |
| `resources.limits.memory` | Memory limit per pod | `512Mi` |
| `service.type` | Kubernetes Service type | `LoadBalancer` |
| `service.mqttPort` | MQTT listener port | `1884` (change to `1883` after testing) |
| `config.allowAnonymous` | Allow unauthenticated clients | `false` |
| `config.maxConnections` | Max clients per node | `10000` |
| `config.persistentStorage.enabled` | Enable persistent volumes | `true` |
| `config.persistentStorage.size` | PVC size per pod | `1Gi` |
| `secretName` | Kubernetes Secret name | `vernemq-secrets` |
| `onepassword.itemPath` | 1Password item path | `vaults/k8s-secrets/items/vernemq` |

## User Management

### Creating Users

Users are stored as **plaintext** `username:password` pairs in 1Password (which is already encrypted).
An **init container** automatically generates bcrypt password hashes on pod startup.

**Create user credentials:**
```
# Format: username:password (one per line)
homeassistant:mySecurePassword123
zigbee2mqtt:anotherPassword456
zwave:yetAnotherPass789
admin:adminPassword000
```

**Add to 1Password:**
1. Go to `vaults/k8s-secrets/items/vernemq`
2. Add field `users` (type: password or text)
3. Paste the user credentials (plaintext)
4. 1Password Connect operator syncs to Kubernetes Secret
5. Init container generates `/vernemq/etc/vmq.passwd` with bcrypt hashes

### Updating Users

To add/remove/change users:
1. Update the `users` field in 1Password
2. Restart VerneMQ pods (or wait for automatic restart):
   ```bash
   kubectl rollout restart statefulset vernemq
   ```

**Note:** Pods automatically restart when ConfigMaps or Secrets change (via checksum annotations).

### Access Control (ACLs)

Modify `templates/configmap.yaml` to define topic permissions:

```
# Allow users to publish/subscribe to their own topics
pattern write home/%u/#
pattern read home/%u/#

# All users can read from sensors
pattern read sensors/#

# Admin has full access
user admin
pattern all #
```

Syntax:
- `%u` = username placeholder
- `%c` = client ID placeholder
- `#` = multi-level wildcard
- `+` = single-level wildcard

## Deployment

This chart is deployed via ArgoCD ApplicationSet (auto-discovery).

**To deploy:**
```bash
git add apps/vernemq/
git commit -m "Add VerneMQ MQTT broker"
git push origin main
```

ArgoCD will automatically:
1. Detect the new chart in `apps/vernemq/`
2. Create Application `app.vernemq`
3. Deploy StatefulSet and Services
4. Sync 1Password secrets

## Monitoring

### Check Cluster Status

```bash
# Pod status
kubectl get pods -l app=vernemq

# Cluster members
kubectl exec -it vernemq-0 -- vmq-admin cluster show

# Connected clients
kubectl exec -it vernemq-0 -- vmq-admin session show

# Metrics (Prometheus format)
kubectl port-forward svc/vernemq 8888:8888
curl http://localhost:8888/metrics
```

### Useful vmq-admin Commands

```bash
# Show all listeners
kubectl exec -it vernemq-0 -- vmq-admin listener show

# Show plugin status
kubectl exec -it vernemq-0 -- vmq-admin plugin show

# Show cluster status
kubectl exec -it vernemq-0 -- vmq-admin cluster show

# Show session details
kubectl exec -it vernemq-0 -- vmq-admin session show --client-id <client-id>
```

## Testing

### Test MQTT Connection

```bash
# Start test pod with mosquitto clients
kubectl run mqtt-test --rm -it --image=eclipse-mosquitto:2 --restart=Never -- sh

# Inside the pod:
VERNEMQ_IP=$(nslookup vernemq | grep Address | tail -1 | awk '{print $2}')

# Publish test message
mosquitto_pub -h $VERNEMQ_IP -p 1883 -u homeassistant -P <password> -t "test/topic" -m "Hello VerneMQ"

# Subscribe to topic
mosquitto_sub -h $VERNEMQ_IP -p 1883 -u homeassistant -P <password> -t "test/#" -v
```

## Troubleshooting

### Pods Not Starting

```bash
# Check pod logs
kubectl logs vernemq-0

# Check events
kubectl describe pod vernemq-0

# Verify secret exists
kubectl get secret vernemq-secrets
kubectl get secret vernemq-secrets -o jsonpath='{.data}' | jq
```

### Cluster Not Forming

```bash
# Check headless service DNS
kubectl run dns-test --rm -it --image=busybox --restart=Never -- nslookup vernemq-headless

# Should return 3 IPs (one per pod)

# Check Erlang port connectivity
kubectl exec -it vernemq-0 -- nc -zv vernemq-1.vernemq-headless 44053
```

### Authentication Issues

```bash
# Verify vmq.passwd in secret
kubectl get secret vernemq-secrets -o jsonpath='{.data.vmq\.passwd}' | base64 -d

# Check auth logs
kubectl logs vernemq-0 | grep -i auth

# Test with mosquitto
mosquitto_pub -h <vernemq-ip> -p 1883 -u <user> -P <pass> -t "test" -m "test" -d
```

## Migration from EMQX

See [EMQX-TO-VERNEMQ-MIGRATION.md](../../docs/EMQX-TO-VERNEMQ-MIGRATION.md) for detailed migration instructions.

## Resources

- [VerneMQ Documentation](https://docs.vernemq.com/)
- [VerneMQ GitHub](https://github.com/vernemq/vernemq)
- [Docker Hub](https://hub.docker.com/r/vernemq/vernemq)
- [Kubernetes Deployment Guide](https://docs.vernemq.com/guides/kubernetes)
