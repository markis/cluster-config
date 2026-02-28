# EMQX to VerneMQ Migration - Implementation Summary

## What Was Created

This migration provides a complete VerneMQ Helm chart and migration documentation for replacing EMQX in your k3s Raspberry Pi cluster.

### Directory Structure

```
cluster-config/
├── apps/
│   ├── mqtt/                    # Existing EMQX chart (to be removed later)
│   └── vernemq/                 # NEW: VerneMQ chart
│       ├── Chart.yaml           # Chart metadata
│       ├── values.yaml          # Configuration values
│       ├── README.md            # Chart documentation
│       ├── config/              # External configuration files
│       │   ├── generate-passwd.sh     # Init container script
│       │   └── vmq.acl                # ACL configuration
│       └── templates/
│           ├── statefulset.yaml        # VerneMQ 3-replica cluster
│           ├── services.yaml           # LoadBalancer + headless service
│           ├── configmap.yaml          # Loads files from config/
│           ├── rbac.yaml               # ServiceAccount, Role, RoleBinding
│           ├── onepassword-item.yaml   # 1Password secret integration
│           └── configmap-users-example.yaml  # Documentation only
└── docs/
    ├── EMQX-TO-VERNEMQ-MIGRATION.md  # Detailed migration guide
    ├── EMQX-TO-VERNEMQ-QUICKSTART.md # Quick start guide
    └── EMQX-TO-VERNEMQ-SUMMARY.md    # This file
```

## Key Features Implemented

### 1. VerneMQ Helm Chart (`apps/vernemq/`)

✅ **StatefulSet Configuration**
- 3 replicas for HA
- Kubernetes-based auto-discovery
- ARM64 node selector for Raspberry Pi
- Persistent volumes (1Gi per pod) for session/message storage
- Resource limits tuned for Raspberry Pi (256Mi-512Mi RAM, 200m-400m CPU)
- **Checksum annotations** for automatic pod restarts on config/secret changes
- **Init container** for automatic password hash generation

✅ **Clustering**
- Native Erlang clustering via headless Service DNS
- Automatic pod discovery using label selector
- Erlang cookie-based cluster authentication (from 1Password)

✅ **Authentication**
- File-based password authentication (`vmq.passwd`)
- Bcrypt password hashing
- Anonymous access disabled by default
- Multiple user support

✅ **Services**
- **LoadBalancer Service**: Exposes MQTT (1883) and metrics (8888)
- **Headless Service**: Provides DNS for clustering

✅ **Security**
- 1Password integration for secrets
- RBAC with minimal permissions (pod list/watch)
- ServiceAccount for pod identity

✅ **Monitoring**
- Prometheus metrics on port 8888
- Liveness, readiness, and startup probes
- Detailed health checks

### 2. User Management

✅ **Automatic Password Hash Generation** (`config/generate-passwd.sh`)
- Init container script loaded from external file
- Reads plaintext `username:password` from 1Password Secret
- Generates bcrypt hashes automatically on pod startup
- No manual hash generation needed!

✅ **1Password Secret Format** (Simple!)
Required fields in `vaults/k8s-secrets/items/vernemq`:
- `erlang-cookie`: Cluster authentication cookie
- `users`: Plaintext user credentials

Example `users` format:
```
homeassistant:mySecurePassword123
zigbee2mqtt:anotherPassword456
admin:adminPassword000
```

✅ **Automatic Updates**
- Pods have checksum annotations for configs and secrets
- When you update users in 1Password, pods automatically restart
- No manual intervention needed to apply password changes

### 3. ACL Configuration

✅ **External Configuration File** (`config/vmq.acl`)
- ACL rules stored in external file
- Loaded via ConfigMap using `.Files.Glob` pattern
- Easy to edit and maintain

✅ **Default ACL** (permissive for testing)
```
pattern all #
```

✅ **Production ACL Example** (edit `config/vmq.acl`)
```
# Users can write to home/<username>/*
pattern write home/%u/#

# Users can read from home/<username>/*
pattern read home/%u/#

# All users can read from sensors/*
pattern read sensors/#

# Admin has full access
user admin
pattern all #
```

✅ **Automatic Updates**
- ACL changes trigger pod restarts (via checksum annotations)
- Edit `config/vmq.acl`, commit, push - pods automatically reload

### 4. Migration Documentation

✅ **Comprehensive Migration Guide** (`docs/EMQX-TO-VERNEMQ-MIGRATION.md`)
- Prerequisites and secret setup
- 9-step migration workflow
- Blue-Green deployment strategy
- Rollback procedures
- Troubleshooting guide
- Configuration reference
- Performance tuning tips

## Differences from EMQX Chart

| Aspect | EMQX (old) | VerneMQ (new) |
|--------|-----------|---------------|
| **Image** | `emqx/emqx:5.8.8` | `vernemq/vernemq:2.0.1-alpine` |
| **Auth Backend** | Redis sidecar | File-based (vmq.passwd) |
| **Dashboard** | Web UI on port 18083 | CLI only (`vmq-admin`) |
| **Configuration** | ConfigMap + env vars | Primarily env vars |
| **Sidecars** | Redis container | None |
| **Memory Usage** | Higher (EMQX + Redis) | Lower (single container) |
| **ACL Format** | Erlang syntax | Pattern syntax |
| **Password Hash** | SHA256 with salt (Redis) | Bcrypt (file) |

## Migration Strategy Overview

The migration uses a **Blue-Green deployment** with **port separation** (no need for separate IPs):

```
Phase 1: Deploy VerneMQ on Port 1884
┌──────────────────┐
│  EMQX (port 1883)│ ← relayd (10.0.0.1:1883) - production traffic
│     (active)     │
└──────────────────┘

┌──────────────────┐
│VerneMQ (port 1884)│ ← Available for testing on 10.0.0.1:1884
│      (testing)   │
└──────────────────┘

Phase 2: Test VerneMQ on Port 1884
- Test clients connect to 10.0.0.1:1884
- Production traffic still on 10.0.0.1:1883 (EMQX)
- Both brokers running simultaneously

Phase 3: Switch VerneMQ to Port 1883
- Update values.yaml: mqttPort: 1884 → 1883
- VerneMQ redeploys on port 1883

Phase 4: Cutover via OPNsense UI
- Update relayd backend pool in OPNsense UI
- Point to VerneMQ instead of EMQX
- No SSH/scripts needed

Phase 5: Verify and Remove EMQX
┌──────────────────┐
│VerneMQ (port 1883)│ ← relayd (10.0.0.1:1883) - production traffic
│     (active)     │
└──────────────────┘
```

**Benefits:**
- ✅ No need for separate LoadBalancer IPs
- ✅ Test VerneMQ on different port while EMQX serves production
- ✅ Easy rollback via OPNsense UI (no SSH needed)
- ✅ Both brokers accessible simultaneously during testing
- ✅ Simple port change via GitOps

## Next Steps

To begin migration:

1. **Prepare 1Password Secrets**
   ```bash
   # Generate Erlang cookie
   openssl rand -base64 32
   
   # Generate user passwords
   cd apps/vernemq/scripts
   ./generate-vmq-passwd.sh homeassistant <password>
   ./generate-vmq-passwd.sh zigbee2mqtt <password>
   # ... repeat for all users
   
   # Add to 1Password at vaults/k8s-secrets/items/vernemq
   ```

2. **Deploy VerneMQ Chart**
   ```bash
   git add apps/vernemq/
   git commit -m "feat(mqtt): add VerneMQ broker for EMQX migration"
   git push origin main
   ```

3. **Follow Migration Guide**
   See `docs/EMQX-TO-VERNEMQ-MIGRATION.md` for detailed steps

## Validation Checklist

Before proceeding with migration, verify:

- [ ] Helm chart lints without errors: `helm lint apps/vernemq --strict`
- [ ] Templates render correctly: `helm template apps/vernemq --debug`
- [ ] 1Password item exists with required fields (`erlang-cookie`, `vmq.passwd`)
- [ ] All MQTT users are listed in `vmq.passwd` with correct bcrypt hashes
- [ ] Default StorageClass is configured in your k3s cluster
- [ ] You have documented your current EMQX user list for reference

## Testing After Deployment

Once VerneMQ is deployed:

1. **Cluster Formation**
   ```bash
   kubectl exec -it vernemq-0 -- vmq-admin cluster show
   # Should show 3 nodes
   ```

2. **Authentication Test**
   ```bash
   kubectl run mqtt-test --rm -it --image=eclipse-mosquitto:2 --restart=Never -- sh
   VERNEMQ_IP=$(nslookup vernemq | grep Address | tail -1 | awk '{print $2}')
   mosquitto_pub -h $VERNEMQ_IP -p 1883 -u <user> -P <pass> -t "test" -m "test"
   ```

3. **Metrics Check**
   ```bash
   kubectl port-forward svc/vernemq 8888:8888
   curl http://localhost:8888/metrics | grep vmq_mqtt
   ```

## Rollback Plan

If issues occur:

1. **Quick Rollback** (revert relayd via OPNsense UI)
   - Open OPNsense Web UI: `https://10.0.0.1`
   - Navigate to: **Services → Load Balancer → Pools**
   - Change MQTT backend pool back to EMQX service IP
   - Click **Save** → **Apply**
   - Clients automatically reconnect to EMQX

2. **Full Rollback** (remove VerneMQ)
   ```bash
   rm -rf apps/vernemq/
   git add apps/vernemq/
   git commit -m "revert(mqtt): remove VerneMQ, rollback to EMQX"
   git push origin main
   ```
   Then update relayd via OPNsense UI (see step 1)

## Support and Troubleshooting

- **Migration Guide**: `docs/EMQX-TO-VERNEMQ-MIGRATION.md`
- **Chart README**: `apps/vernemq/README.md`
- **VerneMQ Docs**: https://docs.vernemq.com/
- **VerneMQ Logs**: `kubectl logs vernemq-0`

## Files to Review Before Migration

1. **apps/vernemq/values.yaml** - Adjust resource limits if needed
2. **apps/vernemq/templates/configmap.yaml** - Review ACL rules
3. **docs/EMQX-TO-VERNEMQ-MIGRATION.md** - Read complete migration guide
4. **1Password item** - Verify all secrets are correctly configured

## Estimated Timeline

- **Preparation**: 30-60 minutes (secrets, password hashes)
- **Deployment**: 5-10 minutes (ArgoCD sync)
- **Testing**: 1-2 hours (cluster verification, MQTT tests)
- **Cutover**: 5 minutes (relayd config change)
- **Monitoring**: 24-48 hours (stability verification)
- **EMQX Removal**: 5 minutes (after 1 week of stability)

**Total**: 1-2 days of active work, 1 week of monitoring
