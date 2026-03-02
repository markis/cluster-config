# Z-Wave JS UI

Z-Wave JS UI is a fully featured Z-Wave Control Panel and MQTT Gateway. This Helm chart deploys
Z-Wave JS UI to your Kubernetes cluster.

## Prerequisites

- Kubernetes cluster
- Helm 3.x
- 1Password Connect operator (for secrets management)
- SLZB-MRW10U network Z-Wave adapter (accessible at `tcp://10.0.0.8:6638`)

## Configuration

### Required 1Password Secrets

Create a 1Password item at `vaults/k8s-secrets/items/zwave-js` with the following fields:

- `mqtt-username`: MQTT broker username
- `mqtt-password`: MQTT broker password
- `zwave-s2-access-control`: S2 Access Control security key (32 hex characters)
- `zwave-s0-legacy`: S0 Legacy security key (32 hex characters)
- `zwave-s2-unauthenticated`: S2 Unauthenticated security key (32 hex characters)
- `zwave-s2-authenticated`: S2 Authenticated security key (32 hex characters)
- `session-secret`: Session secret for web UI (random string)
- `backup-ssh-key`: SSH private key for backup destination

### Key Configuration Options

Edit `values.yaml` to customize:

- **Network Adapter**: Configured for SLZB-MRW10U at `tcp://10.0.0.8:6638`
- **MQTT**: Enable/disable MQTT integration and configure broker settings
- **Home Assistant**: Enable/disable Home Assistant discovery
- **Ingress**: Set your domain name in `ingress.host`
- **Backup**: Configure backup destination and schedule

## Installation

```bash
# Install with Helm
helm install zwave-js . -n default

# Or with custom values
helm install zwave-js . -n default -f custom-values.yaml
```

## Accessing the UI

Once deployed, access the web interface at: `https://zwave.markis.network` (or your configured ingress host)

Default port: 3000 (mapped to service port 8091)

## Backup and Restore

### Automatic Backups

Backups run automatically according to the schedule in `values.yaml` (default: daily at 3 AM).

### Manual Restore

1. Set `restore.enabled: true` in `values.yaml`
2. Set `restore.backupFile` to the backup filename (e.g., "zwave-js-20260216-030000.tar.gz")
3. Apply the changes: `kubectl apply -k .` or sync with ArgoCD
4. Monitor: `kubectl logs -f job/zwave-js-restore`
5. Delete the job: `kubectl delete job zwave-js-restore`
6. Set `restore.enabled: false` and reapply
7. Restart the StatefulSet: `kubectl rollout restart statefulset/zwave-js`

## Security Keys

Z-Wave JS UI requires security keys for secure device pairing. Generate new keys or use existing ones:

```bash
# Generate random keys (32 hex characters each)
openssl rand -hex 16
```

Store these keys securely in 1Password and never commit them to version control.

## Troubleshooting

### Check pod status
```bash
kubectl get pods -l app=zwave-js
kubectl logs -f zwave-js-0
```

### Check configuration
```bash
kubectl exec -it zwave-js-0 -- cat /usr/src/app/store/settings.json
```

### Z-Wave adapter connection issues
Ensure the SLZB-MRW10U network adapter is accessible at `10.0.0.8:6638` from within the cluster. Test connectivity:
```bash
kubectl exec -it zwave-js-0 -- nc -zv 10.0.0.8 6638
```

## References

- [Z-Wave JS UI Documentation](https://zwave-js.github.io/zwave-js-ui/)
- [Z-Wave JS Documentation](https://zwave-js.github.io/node-zwave-js/)
