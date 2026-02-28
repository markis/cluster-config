# EMQX to VerneMQ Migration - Quick Start

This is a condensed version of the migration process. For detailed information, see [EMQX-TO-VERNEMQ-MIGRATION.md](EMQX-TO-VERNEMQ-MIGRATION.md).

## Prerequisites (2 minutes)

### 1. Generate Erlang Cookie
```bash
openssl rand -base64 32
# Example output: kX7mN4pQ8rS2tU5vW9yZ1aB3cD6eF8gH0iJ2kL4mN7oP
```

### 2. Create User Credentials File
Create a simple text file with `username:password` (one per line):

```
homeassistant:mySecurePassword123
zigbee2mqtt:anotherPassword456
zwave:yetAnotherPass789
admin:adminPassword000
```

**Note:** These are plaintext passwords (stored in encrypted 1Password). The init container will generate bcrypt hashes automatically.

### 3. Add to 1Password
1. Open 1Password
2. Navigate to `vaults/k8s-secrets/items/vernemq`
3. Add two fields:
   - **Field**: `erlang-cookie` (password type)
   - **Value**: `<cookie from step 1>`
   - **Field**: `users` (password or text type)
   - **Value**: `<paste user credentials from step 2>`
4. Save

## Deploy VerneMQ (10 minutes)

```bash
# Commit and push VerneMQ chart
git add apps/vernemq/
git commit -m "feat(mqtt): add VerneMQ broker for EMQX migration"
git push origin main

# Wait for deployment
kubectl get pods -l app=vernemq -w

# Expected: 3 pods running
# vernemq-0   1/1   Running   0   2m
# vernemq-1   1/1   Running   0   2m
# vernemq-2   1/1   Running   0   2m
```

## Verify VerneMQ (5 minutes)

### Check Cluster Status
```bash
kubectl exec -it vernemq-0 -- vmq-admin cluster show

# Expected output:
# +----------------------+-------+
# |        Node          |Running|
# +----------------------+-------+
# |VerneMQ@vernemq-0...  |  true |
# |VerneMQ@vernemq-1...  |  true |
# |VerneMQ@vernemq-2...  |  true |
# +----------------------+-------+
```

### Test MQTT Connection
```bash
# Start test pod
kubectl run mqtt-test --rm -it --image=eclipse-mosquitto:2 --restart=Never -- sh

# Inside test pod:
VERNEMQ_IP=$(nslookup vernemq | grep Address | tail -1 | awk '{print $2}')

# Test publish on port 1884 (use your actual credentials)
mosquitto_pub -h $VERNEMQ_IP -p 1884 -u homeassistant -P <password> -t "test/topic" -m "Hello VerneMQ"

# Test subscribe (in another terminal)
kubectl run mqtt-sub --rm -it --image=eclipse-mosquitto:2 --restart=Never -- sh
VERNEMQ_IP=$(nslookup vernemq | grep Address | tail -1 | awk '{print $2}')
mosquitto_sub -h $VERNEMQ_IP -p 1884 -u homeassistant -P <password> -t "test/#" -v

# Test from external (via relayd)
mosquitto_pub -h 10.0.0.1 -p 1884 -u homeassistant -P <password> -t "test/external" -m "Testing via relayd"
```

## Switch VerneMQ to Port 1883 (5 minutes)

Once VerneMQ is verified on port 1884:

```bash
# Edit values.yaml
vi apps/vernemq/values.yaml
# Change: mqttPort: 1884 → mqttPort: 1883

# Commit and push
git add apps/vernemq/values.yaml
git commit -m "feat(mqtt): switch VerneMQ to port 1883 for production"
git push origin main

# Wait for pods to restart
kubectl get pods -l app=vernemq -w
```

## Update relayd (2 minutes)

### Get VerneMQ LoadBalancer IP
```bash
kubectl get svc vernemq -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# Example output: 10.43.100.123
```

### Update via OPNsense UI
1. Open OPNsense Web UI: `https://10.0.0.1`
2. Navigate to: **Services → Load Balancer → Pools**
3. Find the MQTT backend pool
4. Update server IP to VerneMQ LoadBalancer IP (from kubectl above)
5. Click **Save** → **Apply**

## Monitor Cutover (15 minutes)

### Watch VerneMQ Connections
```bash
# Should increase as clients reconnect
kubectl exec -it vernemq-0 -- vmq-admin session show
```

### Watch EMQX Connections
```bash
# Should drop to zero
kubectl exec -it mqtt-0 -- emqx ctl clients list
```

### Check Application Logs
```bash
# Home Assistant, Zigbee2MQTT, Z-Wave JS, etc.
kubectl logs -f deployment/zigbee2mqtt
kubectl logs -f deployment/zwave-js
```

## Verify Stability (24-48 hours)

Monitor for 1-2 days to ensure stability:

```bash
# Check VerneMQ metrics
kubectl exec -it vernemq-0 -- vmq-admin metrics show

# Check pod resource usage
kubectl top pods -l app=vernemq

# Check for errors
kubectl logs vernemq-0 --tail=100 | grep -i error
```

## Remove EMQX (after 1 week)

Once VerneMQ is stable for at least 1 week:

```bash
# Remove EMQX chart
rm -rf apps/mqtt/

git add apps/mqtt/
git commit -m "chore(mqtt): remove EMQX broker after VerneMQ migration"
git push origin main
```

## Rollback (if needed)

If issues occur:

### Quick Rollback (relayd only)
1. Open OPNsense Web UI: `https://10.0.0.1`
2. Navigate to: **Services → Load Balancer → Pools**
3. Change MQTT backend pool back to EMQX service IP
4. Click **Save** → **Apply**

### Full Rollback (remove VerneMQ)
```bash
rm -rf apps/vernemq/
git add apps/vernemq/
git commit -m "revert(mqtt): remove VerneMQ, rollback to EMQX"
git push origin main
```
Then update relayd via OPNsense UI (see above)

## Troubleshooting

### Pods Not Starting
```bash
kubectl describe pod vernemq-0
kubectl logs vernemq-0
kubectl get secret vernemq-secrets  # Verify secret exists
```

### Cluster Not Forming
```bash
kubectl exec -it vernemq-0 -- vmq-admin cluster show
kubectl run dns-test --rm -it --image=busybox --restart=Never -- nslookup vernemq-headless
```

### Authentication Failures
```bash
# Verify vmq.passwd in secret
kubectl get secret vernemq-secrets -o jsonpath='{.data.vmq\.passwd}' | base64 -d

# Check VerneMQ logs
kubectl logs vernemq-0 | grep -i auth
```

### Clients Not Connecting
```bash
# Verify relayd is using VerneMQ IP
# On relayd host:
sudo cat /etc/relayd.conf | grep mqtt

# Verify VerneMQ LoadBalancer IP
kubectl get svc vernemq -o wide
```

## Timeline Summary

| Phase | Duration | Description |
|-------|----------|-------------|
| Preparation | 5 min | Generate secrets, create 1Password item |
| Deployment | 10 min | Push to Git, wait for ArgoCD sync |
| Verification | 5 min | Test cluster and MQTT connections |
| Cutover | 5 min | Update relayd configuration |
| Monitoring | 24-48 hrs | Watch for issues, verify stability |
| Cleanup | 5 min | Remove EMQX (after 1 week) |

**Total Active Time**: ~30 minutes  
**Total Timeline**: 1-2 weeks (including monitoring period)

## Next Steps

For detailed information:
- **Full Migration Guide**: [EMQX-TO-VERNEMQ-MIGRATION.md](EMQX-TO-VERNEMQ-MIGRATION.md)
- **Implementation Summary**: [EMQX-TO-VERNEMQ-SUMMARY.md](EMQX-TO-VERNEMQ-SUMMARY.md)
- **Chart Documentation**: [apps/vernemq/README.md](../apps/vernemq/README.md)
