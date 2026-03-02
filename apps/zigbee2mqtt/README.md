# Zigbee2MQTT

Zigbee to MQTT bridge for controlling Zigbee devices, deployed on Kubernetes.

## Configuration

- **Zigbee Adapter**: SLZB-MRW10U at `tcp://10.0.0.8:7638` (zstack adapter)
- **MQTT Broker**: EMQX at `mqtt.default.svc.cluster.local:1883`
- **Web UI**: `https://zigbee.markis.network` (via Traefik ingress)
- **Home Assistant**: MQTT discovery enabled

## Prerequisites

### 1. 1Password Secret

Create a 1Password item in `k8s-secrets` vault named `zigbee2mqtt` with:

| Field | Description | Example |
|-------|-------------|---------|
| `mqtt-username` | Username for EMQX broker | `zigbee2mqtt` |
| `mqtt-password` | Password for EMQX broker | `your-secure-password` |
| `zigbee-pan-id` | Zigbee PAN ID (0-65535) | `8397` |
| `zigbee-ext-pan-id` | Extended PAN ID (8 bytes as JSON array) | `[19, 56, 98, 54, 49, 88, 100, 169]` |
| `zigbee-network-key` | Network encryption key (16 bytes as JSON array) | `[33, 178, 70, 38, 20, 158, 0, 187, 35, 115, 240, 18, 219, 196, 177, 87]` |
| `backup-ssh-key` | Private SSH key for backup node access (optional, for backups) | `-----BEGIN OPENSSH PRIVATE KEY-----...` |

**Generate secure values:**
```bash
# Generate PAN ID (random number 0-65535)
python3 -c "import secrets; print(secrets.randbelow(0xFFFF))"

# Generate Extended PAN ID (8 random bytes as JSON array)
python3 -c "import secrets; print('[' + ', '.join(str(secrets.randbelow(256)) for _ in range(8)) + ']')"

# Generate Network Key (16 random bytes as JSON array)
python3 -c "import secrets; print('[' + ', '.join(str(secrets.randbelow(256)) for _ in range(16)) + ']')"
```

### 2. OPNsense Configuration

Configure external access through OPNsense:

**Unbound DNS Override:**
- Host: `zigbee`
- Domain: `markis.network`
- IP: `10.0.0.1`

**Caddy Domain:** `zigbee.markis.network`

**Caddy Handler:**
- Domain: `zigbee.markis.network`
- Upstream: `10.0.0.1:8080`

## Storage

Uses `local-path` StorageClass (default for k3s), which means:
- PVC is bound to a specific node's local storage
- Pod will always run on the node where the PVC was created
- Data persists across pod restarts

## Backup & Restore

Automated backups help with node maintenance and disaster recovery.

### Automated Backups

A CronJob runs daily at 2 AM to backup zigbee2mqtt data:

- **Destination**: `10.0.0.10:/mnt/backups/zigbee2mqtt`
- **Schedule**: Daily at 2 AM
- **Retention**: Last 7 backups
- **Format**: `zigbee2mqtt-YYYYMMDD-HHMMSS.tar.gz`

**Prerequisites:**
1. Ensure `/mnt/backups/zigbee2mqtt` directory exists on `10.0.0.10`
2. Add `backup-ssh-key` to 1Password secret (private key for root@10.0.0.10)

**View backup logs:**
```bash
kubectl get cronjobs
kubectl logs -l app=zigbee2mqtt,component=backup
```

### Manual Backup

Trigger an immediate backup:

```bash
kubectl create job --from=cronjob/zigbee2mqtt-backup zigbee2mqtt-backup-manual
kubectl logs -f job/zigbee2mqtt-backup-manual
```

### Restore from Backup

When you need to move to a different node or recover from failure:

**1. List available backups:**
```bash
ssh root@10.0.0.10 "ls -lh /mnt/backups/zigbee2mqtt/"
```

**2. Scale down zigbee2mqtt:**
```bash
kubectl scale statefulset zigbee2mqtt --replicas=0
```

**3. Delete the PVC (this will delete the local data):**
```bash
kubectl delete pvc data-zigbee2mqtt-0
```

**4. Create restore job:**
```bash
# Edit the restore job to set BACKUP_FILE
kubectl edit -f templates/restore-job.yaml
# Set: BACKUP_FILE=zigbee2mqtt-20260210-020000.tar.gz

# Or use kubectl patch:
kubectl get job zigbee2mqtt-restore -o yaml | \
  sed 's/value: ""/value: "zigbee2mqtt-20260210-020000.tar.gz"/' | \
  kubectl apply -f -

# Monitor restore
kubectl logs -f job/zigbee2mqtt-restore
```

**5. Scale up zigbee2mqtt:**
```bash
kubectl scale statefulset zigbee2mqtt --replicas=1
```

The StatefulSet will create a new PVC on whichever node it gets scheduled to, and the restore job
will populate it with the backup data.

### Moving to a Different Node

If you need to perform maintenance on the node running zigbee2mqtt:

1. **Backup current state** (manual or wait for scheduled backup)
2. **Cordon the old node:**
   ```bash
   kubectl cordon <old-node-name>
   ```
3. **Scale down and delete PVC:**
   ```bash
   kubectl scale statefulset zigbee2mqtt --replicas=0
   kubectl delete pvc data-zigbee2mqtt-0
   ```
4. **Restore from backup** (see above)
5. **Scale up** - pod will start on a different node
6. **Uncordon old node when maintenance is complete:**
   ```bash
   kubectl uncordon <old-node-name>
   ```

## Troubleshooting

### Check pod status
```bash
kubectl get pods -l app=zigbee2mqtt
kubectl describe pod zigbee2mqtt-0
kubectl logs -f zigbee2mqtt-0
```

### Check MQTT connection
```bash
kubectl logs -f zigbee2mqtt-0 | grep -i mqtt
```

### Check Zigbee adapter connection
```bash
kubectl logs -f zigbee2mqtt-0 | grep -i serial
```

### Access web UI locally (if ingress not working)
```bash
kubectl port-forward svc/zigbee2mqtt 8080:8080
# Open http://localhost:8080
```

### Check storage
```bash
kubectl get pvc
kubectl get pv
```

## Pairing Devices

1. Access web UI at `https://zigbee.markis.network`
2. Click "Permit Join" to allow new devices
3. Put your Zigbee device in pairing mode
4. Device should appear in the UI
5. Configure device name and settings

## Home Assistant Integration

Devices are automatically discovered in Home Assistant via MQTT:
- Discovery topic: `homeassistant`
- Base topic: `zigbee2mqtt`
- Status topic: `homeassistant/status`

Check Home Assistant → Configuration → Integrations → MQTT for discovered devices.
