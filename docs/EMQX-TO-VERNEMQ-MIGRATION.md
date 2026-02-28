# EMQX to VerneMQ Migration Guide

This guide provides step-by-step instructions for migrating from EMQX to VerneMQ in a k3s Raspberry Pi cluster using GitOps (ArgoCD).

## Overview

- **Current**: EMQX MQTT broker (`apps/mqtt`)
- **Target**: VerneMQ MQTT broker (`apps/vernemq`)
- **External Entry**: `10.0.0.1:1883` (via `relayd` - unchanged)
- **Strategy**: Blue-Green deployment with traffic cutover via `relayd` configuration

## Prerequisites

1. **1Password Secret Setup**: Create a 1Password item at `vaults/k8s-secrets/items/vernemq` with:
   - `erlang-cookie`: Random string for Erlang clustering (e.g., `openssl rand -base64 32`)
   - `vmq.passwd`: VerneMQ password file (see "User Management" section below)

2. **Storage**: Ensure your cluster has a default StorageClass for PersistentVolumeClaims

3. **Cluster Access**: Ability to commit and push to this Git repository

## User Management in VerneMQ

### How It Works

VerneMQ uses a password file (`vmq.passwd`) for authentication. The passwords are stored in **plaintext** in 1Password (which is already encrypted), and an **init container** automatically generates the bcrypt-hashed `vmq.passwd` file when each pod starts.

**Benefits:**
- ✅ Simple: Just store `username:password` in 1Password
- ✅ No manual hash generation needed
- ✅ Secure: 1Password encrypts the plaintext passwords
- ✅ GitOps-friendly: Update 1Password, restart pods, done

### Setting Up Users

#### Format in 1Password

Store users in the `users` field with one user per line:
```
username:password
```

**Example:**
```
homeassistant:mySecurePassword123
zigbee2mqtt:anotherPassword456
zwave:yetAnotherPass789
admin:adminPassword000
```

#### Storing in 1Password

1. Go to `vaults/k8s-secrets/items/vernemq` in 1Password
2. Add a new field:
   - **Field name**: `users`
   - **Field type**: `password` (or `text`)
   - **Value**: Paste the user credentials (one per line)
3. The 1Password Connect operator will sync this to Kubernetes as a Secret

#### How the Init Container Works

When each VerneMQ pod starts:
1. The **init container** reads `/secrets/users` from the Kubernetes Secret
2. For each `username:password` line, it generates a bcrypt hash using `vmq-passwd`
3. It writes the hashed passwords to `/tmp/vmq.passwd`
4. The main VerneMQ container mounts this file at `/vernemq/etc/vmq.passwd`

**Init Container Script:**
```bash
# Read users from secret (format: username:password per line)
while IFS=: read -r username password; do
  echo "Generating hash for user: $username"
  echo "$password" | vmq-passwd -c /tmp/vmq.passwd "$username"
done < /secrets/users
```

### ACL Configuration

Access control lists (ACLs) are defined in `apps/vernemq/templates/configmap.yaml` (`vmq.acl` file).

**Default (permissive):**
```
pattern all #
```

**Production example (restrictive):**
```
# Users can publish to their own topics
pattern write home/%u/#

# Users can subscribe to their own topics
pattern read home/%u/#

# All users can read from sensors
pattern read sensors/#

# Admin user has full access
user admin
pattern all #
```

Pattern syntax:
- `%u` = username
- `%c` = client ID
- `#` = multi-level wildcard
- `+` = single-level wildcard

## Migration Steps

### Step 1: Prepare 1Password Secrets

1. **Create the `erlang-cookie` secret:**
   ```bash
   openssl rand -base64 32
   # Example output: kX7mN4pQ8rS2tU5vW9yZ1aB3cD6eF8gH0iJ2kL4mN7oP
   ```

2. **Create the `users` file with your MQTT users:**
   
   Format: `username:password` (one per line)
   
   Example:
   ```
   homeassistant:mySecurePassword123
   zigbee2mqtt:anotherPassword456
   zwave:yetAnotherPass789
   admin:adminPassword000
   ```

3. **Add both to 1Password item** `vaults/k8s-secrets/items/vernemq`:
   - **Field**: `erlang-cookie` (type: password)
   - **Value**: `<generated-cookie from step 1>`
   - **Field**: `users` (type: password or text)
   - **Value**: `<paste user credentials from step 2>`

The init container will automatically generate bcrypt password hashes on pod startup.

**Automatic Pod Restarts:**
- Pods have checksum annotations for ConfigMaps and Secrets
- When you update user credentials in 1Password, pods will automatically restart
- This ensures password changes take effect without manual intervention

### Step 2: Deploy VerneMQ Alongside EMQX

Since your cluster uses the ApplicationSet pattern (auto-discovery from `apps/` directory), simply commit the new VerneMQ chart:

```bash
# VerneMQ chart is already in apps/vernemq/
git add apps/vernemq/
git commit -m "feat(mqtt): add VerneMQ broker for migration from EMQX"
git push origin main
```

**What happens:**
- ArgoCD detects the new `apps/vernemq/` directory
- Creates Application `app.vernemq`
- Deploys VerneMQ StatefulSet with 3 replicas
- Creates LoadBalancer Service `vernemq` (separate from EMQX's `mqtt` service)
- Both EMQX and VerneMQ run simultaneously in namespace `default`

### Step 3: Verify VerneMQ Cluster Health

Wait for VerneMQ pods to start and form a cluster:

```bash
# Check pod status
kubectl get pods -l app=vernemq

# Expected output:
# NAME         READY   STATUS    RESTARTS   AGE
# vernemq-0    1/1     Running   0          2m
# vernemq-1    1/1     Running   0          2m
# vernemq-2    1/1     Running   0          2m

# Check cluster status (from any pod)
kubectl exec -it vernemq-0 -- vmq-admin cluster show

# Expected output shows all 3 nodes in the cluster:
# +----------------+-------+
# |      Node      |Running|
# +----------------+-------+
# |VerneMQ@vernemq-0...|  true |
# |VerneMQ@vernemq-1...|  true |
# |VerneMQ@vernemq-2...|  true |
# +----------------+-------+
```

### Step 4: Test VerneMQ with MQTT Clients

VerneMQ is deployed on **port 1884** for testing (EMQX remains on port 1883). This allows both brokers to run simultaneously.

**Test from inside the cluster:**

```bash
# Start a test pod with mosquitto clients
kubectl run mqtt-test --rm -it --image=eclipse-mosquitto:2 --restart=Never -- sh

# Inside the test pod:
# Get the VerneMQ LoadBalancer IP
VERNEMQ_IP=$(nslookup vernemq | grep Address | tail -1 | awk '{print $2}')

# Test connection on port 1884 with credentials
mosquitto_pub -h $VERNEMQ_IP -p 1884 -u homeassistant -P <your-password> -t "test/topic" -m "Hello VerneMQ"

# Subscribe to verify
mosquitto_sub -h $VERNEMQ_IP -p 1884 -u homeassistant -P <your-password> -t "test/#" -v
```

**Test from external clients (via relayd):**

```bash
# On your workstation or IoT device
# Connect to relayd on port 1884 (forwards to VerneMQ)
mosquitto_pub -h 10.0.0.1 -p 1884 -u homeassistant -P <your-password> -t "test/topic" -m "Hello VerneMQ"

# Subscribe
mosquitto_sub -h 10.0.0.1 -p 1884 -u homeassistant -P <your-password> -t "test/#" -v
```

**Expected behavior:**
- Anonymous connections should FAIL (if `allowAnonymous: false`)
- Authenticated connections should SUCCEED on port 1884
- EMQX still works on port 1883 (existing clients unaffected)
- Messages publish/subscribe successfully

### Step 5: Update VerneMQ to Port 1883

Once you've validated VerneMQ works correctly on port 1884, switch it to port 1883:

```bash
# Edit values.yaml
vi apps/vernemq/values.yaml

# Change:
# service:
#   mqttPort: 1884
# To:
# service:
#   mqttPort: 1883

# Commit and push
git add apps/vernemq/values.yaml
git commit -m "feat(mqtt): switch VerneMQ to port 1883 for production"
git push origin main

# Wait for ArgoCD to redeploy VerneMQ
kubectl get pods -l app=vernemq -w
```

**What happens:**
- ArgoCD detects the change
- Triggers rolling restart of VerneMQ pods
- VerneMQ now listens on port 1883 (same as EMQX)
- Both brokers now compete for port 1883 on the LoadBalancer
- **Note:** relayd still points to EMQX (port 1883)

### Step 6: Update relayd to Point to VerneMQ

Now switch `relayd` to point to VerneMQ instead of EMQX using the **OPNsense UI**.

#### Get VerneMQ Service Information

First, get the VerneMQ service details:

```bash
# Get VerneMQ LoadBalancer IP
kubectl get svc vernemq -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# Example output: 10.43.100.123

# Verify the service is listening on port 1883
kubectl get svc vernemq -o wide
```

#### Update relayd via OPNsense UI

1. **Open OPNsense Web UI**: Navigate to your OPNsense interface (e.g., `https://10.0.0.1`)

2. **Go to Load Balancer Settings**:
   - Navigate to: **Services → Load Balancer → Virtual Servers**
   - Find the MQTT virtual server (port 1883)

3. **Update Backend Pool**:
   - Navigate to: **Services → Load Balancer → Pools**
   - Find the MQTT backend pool
   - Update the server entry:
     - **Old**: EMQX service IP/name
     - **New**: VerneMQ LoadBalancer IP (from kubectl above)
   - Click **Save**

4. **Apply Changes**:
   - Click **Apply** to reload the configuration
   - relayd will reload without downtime

**Alternative - If using Virtual IPs:**
- Navigate to: **Firewall → Virtual IPs**
- Update the backend target for port 1883
- Apply changes

**Verification:**
```bash
# From your workstation, test MQTT connection via relayd
mosquitto_pub -h 10.0.0.1 -p 1883 -u homeassistant -P <password> -t "test/cutover" -m "Now using VerneMQ"
```

### Step 7: Monitor Traffic Cutover

After updating `relayd`, monitor both brokers:

```bash
# Watch VerneMQ connections (should increase)
kubectl exec -it vernemq-0 -- vmq-admin session show --limit 100

# Watch EMQX connections (should drop to zero)
kubectl exec -it mqtt-0 -- emqx ctl clients list
```

**Metrics to observe:**
- VerneMQ client connections increase to match previous EMQX count
- EMQX client connections drop to zero (clients reconnect to VerneMQ)
- No client errors in application logs

**Note on Persistent Sessions (QoS 1):**
- Clients with `clean_session=false` will reconnect and resume sessions on VerneMQ
- Messages published to EMQX while clients were disconnected will NOT transfer to VerneMQ
- If critical, manually republish important retained messages (see Step 7)

### Step 8: Migrate Retained Messages (Optional)

If your system relies on retained messages (e.g., Home Assistant discovery topics):

```bash
# Export retained topics from EMQX (manual process)
# 1. Connect to EMQX dashboard at http://<emqx-service-ip>:18083
# 2. Navigate to "Retained Messages"
# 3. Note critical topics and values

# Republish to VerneMQ
kubectl run mqtt-publisher --rm -it --image=eclipse-mosquitto:2 --restart=Never -- sh

# Inside the pod:
VERNEMQ_IP=$(nslookup vernemq | grep Address | tail -1 | awk '{print $2}')

# Republish retained messages with -r flag
mosquitto_pub -h $VERNEMQ_IP -p 1883 -u admin -P <admin-pass> \
  -t "homeassistant/sensor/living_room/config" \
  -m '{"name":"Living Room Temp",...}' \
  -r

# Repeat for all critical retained topics
```

**Automated Alternative:**
Use an MQTT bridge or script to subscribe to `#` on EMQX and republish to VerneMQ (advanced, requires careful handling).

### Step 9: Verify Client Behavior

Monitor your MQTT clients (Home Assistant, Zigbee2MQTT, etc.) for 24-48 hours:

```bash
# Check Home Assistant MQTT integration
# - Should show "Connected" status
# - Devices should respond to commands

# Check Zigbee2MQTT logs
kubectl logs -f deployment/zigbee2mqtt

# Check Z-Wave JS logs
kubectl logs -f deployment/zwave-js

# Verify persistent sessions for QoS 1 clients
kubectl exec -it vernemq-0 -- vmq-admin session show | grep -i "clean_session.*false"
```

### Step 10: Remove EMQX

Once VerneMQ is stable (recommended: 1 week), remove EMQX:

```bash
# Delete the EMQX chart directory
rm -rf apps/mqtt/

git add apps/mqtt/
git commit -m "chore(mqtt): remove EMQX broker after VerneMQ migration"
git push origin main
```

**What happens:**
- ArgoCD detects the directory deletion
- Deletes the `app.mqtt` Application
- Prunes all EMQX resources (StatefulSet, Services, ConfigMaps, etc.)
- VerneMQ remains running as the sole MQTT broker

## Rollback Procedure

If issues occur after switching `relayd` to VerneMQ:

### Quick Rollback (revert relayd configuration)

1. **Open OPNsense Web UI** (e.g., `https://10.0.0.1`)
2. **Navigate to Load Balancer**:
   - Go to: **Services → Load Balancer → Pools**
3. **Update MQTT backend pool**:
   - Change server back to EMQX service IP
   - Click **Save**
4. **Apply changes**:
   - Click **Apply** to reload relayd
5. **Verify clients reconnect to EMQX**:
   ```bash
   mosquitto_pub -h 10.0.0.1 -p 1883 -u homeassistant -P <password> -t "test" -m "Back to EMQX"
   ```

### Full Rollback (remove VerneMQ)

```bash
# Remove VerneMQ chart
rm -rf apps/vernemq/

git add apps/vernemq/
git commit -m "revert(mqtt): remove VerneMQ, rollback to EMQX"
git push origin main

# Revert relayd to point to EMQX (see above)
```

## Troubleshooting

### VerneMQ Pods Not Starting

```bash
# Check pod logs
kubectl logs vernemq-0

# Common issues:
# - Missing 1Password secret: verify `kubectl get secret vernemq-secrets`
# - Permission errors: check RBAC (ServiceAccount, Role, RoleBinding)
# - ARM64 image issue: verify image tag includes "alpine" variant
```

### Cluster Not Forming

```bash
# Check cluster status
kubectl exec -it vernemq-0 -- vmq-admin cluster show

# Verify headless service DNS resolution
kubectl run dns-test --rm -it --image=busybox --restart=Never -- nslookup vernemq-headless

# Should resolve to 3 IPs (one per pod)
```

### Authentication Failures

```bash
# Verify vmq.passwd file in secret
kubectl get secret vernemq-secrets -o jsonpath='{.data.vmq\.passwd}' | base64 -d

# Check VerneMQ logs for auth errors
kubectl logs vernemq-0 | grep -i auth

# Test with different credentials
mosquitto_pub -h <vernemq-ip> -p 1883 -u <user> -P <pass> -t "test" -m "test"
```

### Clients Not Connecting After Cutover

```bash
# Verify relayd is pointing to VerneMQ service IP
# Get VerneMQ LoadBalancer IP:
kubectl get svc vernemq -o wide

# Check relayd logs (on relayd host)
sudo tail -f /var/log/relayd.log

# Verify client credentials match vmq.passwd file
```

## Configuration Reference

### VerneMQ Environment Variables (StatefulSet)

Key environment variables in `apps/vernemq/templates/statefulset.yaml`:

| Variable | Purpose | Example Value |
|----------|---------|---------------|
| `DOCKER_VERNEMQ_NODENAME` | Erlang node name | `VerneMQ@vernemq-0.vernemq-headless.default.svc.cluster.local` |
| `DOCKER_VERNEMQ_DISCOVERY_KUBERNETES` | Enable k8s discovery | `1` |
| `DOCKER_VERNEMQ_KUBERNETES_LABEL_SELECTOR` | Pod selector for clustering | `app=vernemq` |
| `DOCKER_VERNEMQ_ALLOW_ANONYMOUS` | Allow unauthenticated clients | `off` |
| `DOCKER_VERNEMQ_PLUGINS__VMQ_PASSWD` | Enable password file auth | `on` |
| `ERLANG_COOKIE` | Cluster security cookie | (from secret) |

### Resource Limits

Tuned for Raspberry Pi 4/5:

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
  limits:
    memory: "512Mi"
    cpu: "400m"
```

Adjust based on your client load. Monitor with:
```bash
kubectl top pods -l app=vernemq
```

### Persistent Storage

VerneMQ stores session state and retained messages in `/vernemq/data`:

```yaml
config:
  persistentStorage:
    enabled: true
    size: 1Gi
    storageClass: ""  # Uses default StorageClass
```

To disable persistence (not recommended for production):
```yaml
config:
  persistentStorage:
    enabled: false
```

## Performance Tuning

### Max Connections Per Node

Default: 10,000 connections per node (30,000 total across 3 replicas)

Adjust in `values.yaml`:
```yaml
config:
  maxConnections: 20000  # Increase for high-load scenarios
```

### Erlang VM Tuning

For high connection counts, adjust Erlang distribution port range:
```yaml
env:
  - name: DOCKER_VERNEMQ_ERLANG__DISTRIBUTION__PORT_RANGE__MINIMUM
    value: "9100"
  - name: DOCKER_VERNEMQ_ERLANG__DISTRIBUTION__PORT_RANGE__MAXIMUM
    value: "9109"
```

## Monitoring

### Prometheus Metrics

VerneMQ exposes Prometheus metrics on port 8888:

```bash
# Access metrics
kubectl port-forward svc/vernemq 8888:8888
curl http://localhost:8888/metrics
```

**Key metrics:**
- `vmq_mqtt_connack_sent` - Successful connections
- `vmq_mqtt_publish_received` - Messages received
- `vmq_mqtt_publish_sent` - Messages sent
- `vmq_mqtt_subscribe_received` - Subscriptions

### ServiceMonitor (Optional)

If you have Prometheus Operator installed:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: vernemq
  labels:
    app: vernemq
spec:
  selector:
    matchLabels:
      app: vernemq
  endpoints:
    - port: metrics
      interval: 30s
```

## Differences from EMQX

| Feature | EMQX | VerneMQ |
|---------|------|---------|
| **Authentication** | Redis backend (hash + salt) | File-based (bcrypt hashes) |
| **ACLs** | File-based Erlang syntax | File-based pattern syntax |
| **Dashboard** | Built-in web UI (port 18083) | CLI only (`vmq-admin`) |
| **Clustering** | Mnesia + Erlang dist | Plumtree gossip + Erlang dist |
| **Config** | `emqx.conf` (HOCON-like) | Environment variables + files |
| **Sidecars** | Used Redis sidecar | No sidecars needed |

**Impact:**
- **No dashboard**: Use `vmq-admin` CLI for monitoring
- **Simpler auth**: Easier to manage with static password file
- **Less memory**: No Redis sidecar reduces pod memory usage

## Additional Resources

- [VerneMQ Documentation](https://docs.vernemq.com/)
- [VerneMQ Docker Hub](https://hub.docker.com/r/vernemq/vernemq)
- [VerneMQ Kubernetes Guide](https://docs.vernemq.com/guides/kubernetes)
- [MQTT ACL Patterns](https://docs.vernemq.com/configuration/file-auth)

## Support

For issues with this migration:
1. Check VerneMQ pod logs: `kubectl logs vernemq-0`
2. Check ArgoCD sync status: `kubectl get application -n argocd app.vernemq`
3. Review this repository's issues or open a new one
