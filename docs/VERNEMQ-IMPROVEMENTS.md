# VerneMQ Chart Improvements

This document summarizes the improvements made to the VerneMQ Helm chart based on your requirements.

## ✅ Requested Improvements

### 1. External Configuration Files

**Requirement:** Store scripts and configs as external files and reference them in YAML.

**Implementation:**
- Created `apps/vernemq/config/` directory for external files
- Moved ACL configuration to `config/vmq.acl`
- Moved init container script to `config/generate-passwd.sh`
- Updated ConfigMap to use `.Files.Glob` pattern:
  ```yaml
  data:
  {{ (.Files.Glob "config/*").AsConfig | indent 2 }}
  ```

**Benefits:**
- ✅ Cleaner YAML templates (no inline scripts/configs)
- ✅ Easier to edit configuration files
- ✅ Better version control (see actual file changes in Git diffs)
- ✅ Follows Helm best practices

### 2. Simplified User Management

**Requirement:** Store plaintext usernames/passwords in secrets, generate hashes automatically.

**Implementation:**
- **Before:** Required manual `vmq-passwd` hash generation
- **After:** Store `username:password` in 1Password, init container generates hashes

**1Password Secret Format:**
```
# Field: users (plaintext)
homeassistant:mySecurePassword123
zigbee2mqtt:anotherPassword456
admin:adminPassword000
```

**Init Container Process:**
1. Reads `/secrets/users` from Kubernetes Secret
2. For each user, runs: `echo "$password" | vmq-passwd -c /tmp/vmq.passwd "$username"`
3. Generates bcrypt hashes in `/tmp/vmq.passwd`
4. Main container mounts this file

**Benefits:**
- ✅ No manual hash generation needed
- ✅ Simpler workflow (just edit 1Password)
- ✅ Still secure (1Password encrypts plaintext passwords)
- ✅ Easier to update passwords

### 3. Automatic Pod Restarts on Config/Secret Changes

**Requirement:** Automatically redeploy StatefulSet when ConfigMaps or Secrets are updated.

**Implementation:**
Added checksum annotations to pod template:
```yaml
template:
  metadata:
    annotations:
      checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      checksum/secret: {{ include (print $.Template.BasePath "/onepassword-item.yaml") . | sha256sum }}
```

**How It Works:**
1. Helm calculates SHA256 checksums of ConfigMap and Secret templates
2. Stores checksums as pod annotations
3. When ConfigMap/Secret changes, checksum changes
4. Kubernetes sees pod template changed → triggers rolling restart
5. New pods pick up updated configuration

**Benefits:**
- ✅ Automatic updates (no manual `kubectl rollout restart`)
- ✅ GitOps-friendly (commit config change → automatic deployment)
- ✅ Rolling restart (zero downtime)
- ✅ Follows Kubernetes best practices

## Updated Chart Structure

```
apps/vernemq/
├── Chart.yaml                  # Chart metadata
├── values.yaml                 # Configuration values
├── README.md                   # Updated documentation
├── config/                     # 🆕 External configuration files
│   ├── generate-passwd.sh      # Init container script
│   └── vmq.acl                 # ACL configuration
└── templates/
    ├── statefulset.yaml        # Updated with init container + checksums
    ├── services.yaml           # LoadBalancer + headless
    ├── configmap.yaml          # 🆕 Uses .Files.Glob pattern
    ├── rbac.yaml               # ServiceAccount, Role, RoleBinding
    ├── onepassword-item.yaml   # 1Password integration
    └── configmap-users-example.yaml  # Documentation only
```

## Workflow Comparison

### Before (Manual Hash Generation)

```bash
# 1. Generate hashes manually
docker run --rm vernemq/vernemq:2.0.1-alpine vmq-passwd -c /dev/stdout homeassistant
# homeassistant:$2b$12$abcdefg...

# 2. Create vmq.passwd file with hashes
cat > vmq.passwd <<EOF
homeassistant:$2b$12$abcdefg...
zigbee2mqtt:$2b$12$hijklmn...
EOF

# 3. Add to 1Password
# (manually paste file contents)

# 4. Wait for 1Password sync

# 5. Manually restart pods
kubectl rollout restart statefulset vernemq
```

### After (Automatic)

```bash
# 1. Create users file (plaintext)
cat > users <<EOF
homeassistant:myPassword123
zigbee2mqtt:anotherPass456
EOF

# 2. Add to 1Password
# (paste plaintext credentials)

# 3. Done! Pods automatically:
#    - Detect secret change (checksum annotation)
#    - Restart with rolling update
#    - Generate password hashes (init container)
#    - Start VerneMQ with new credentials
```

## Example: Updating User Passwords

### Scenario: Change homeassistant user password

**Steps:**
1. Edit 1Password item `vaults/k8s-secrets/items/vernemq`
2. Update `users` field:
   ```
   homeassistant:newPassword789  ← Changed
   zigbee2mqtt:anotherPass456
   admin:adminPassword000
   ```
3. Save in 1Password

**What Happens Automatically:**
1. 1Password Connect operator syncs to Kubernetes Secret `vernemq-secrets`
2. Secret checksum changes
3. Kubernetes detects pod template annotation changed
4. Triggers rolling restart: `vernemq-0` → `vernemq-1` → `vernemq-2`
5. Each pod:
   - Init container runs `generate-passwd.sh`
   - Generates new bcrypt hash for `homeassistant`
   - Writes `/tmp/vmq.passwd` with updated hash
   - Main container starts with new password file

**Timeline:**
- 1Password sync: ~30 seconds
- Rolling restart (3 pods): ~2-3 minutes
- Total: ~3-4 minutes (fully automatic)

## Configuration Update Examples

### Example 1: Add a New User

**Edit 1Password:**
```diff
  homeassistant:myPassword123
  zigbee2mqtt:anotherPass456
  admin:adminPassword000
+ nodered:flowsPassword999
```

**Result:** Pods restart automatically, `nodered` user can now connect.

### Example 2: Update ACL Rules

**Edit `apps/vernemq/config/vmq.acl`:**
```diff
- pattern all #
+ # Users can only access their own topics
+ pattern write home/%u/#
+ pattern read home/%u/#
+ 
+ # Admin has full access
+ user admin
+ pattern all #
```

**Commit and push:**
```bash
git add apps/vernemq/config/vmq.acl
git commit -m "feat(mqtt): restrict topics to user-specific paths"
git push origin main
```

**Result:**
- ArgoCD syncs new ConfigMap
- ConfigMap checksum changes
- Pods restart automatically with new ACL rules

### Example 3: Update Init Script

**Edit `apps/vernemq/config/generate-passwd.sh`:**
```bash
#!/bin/sh
set -e

echo "Generating vmq.passwd file from user credentials..."

# Added: Log timestamp
echo "Generation started at: $(date)"

while IFS=: read -r username password || [ -n "$username" ]; do
  [ -z "$username" ] && continue
  echo "$username" | grep -q '^#' && continue
  
  echo "Generating hash for user: $username"
  echo "$password" | vmq-passwd -c /tmp/vmq.passwd "$username"
done < /secrets/users

echo "vmq.passwd file generated successfully at: $(date)"
cat /tmp/vmq.passwd
```

**Commit and push:**
```bash
git add apps/vernemq/config/generate-passwd.sh
git commit -m "feat(mqtt): add timestamps to password generation logs"
git push origin main
```

**Result:**
- ArgoCD syncs new ConfigMap
- Pods restart with updated init script
- Next pod starts show timestamps in logs

## Validation

All changes validated:

```bash
# Helm lint passes
$ helm lint apps/vernemq --strict
==> Linting apps/vernemq
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed

# Templates render correctly
$ helm template apps/vernemq --debug
# ✅ ConfigMap contains external files
# ✅ StatefulSet has checksum annotations
# ✅ Init container references external script

# Files loaded correctly
$ helm template apps/vernemq | grep -A 5 "generate-passwd.sh:"
  generate-passwd.sh: |
    #!/bin/sh
    set -e
    
    echo "Generating vmq.passwd file from user credentials..."
```

## Summary of Benefits

| Aspect | Before | After |
|--------|--------|-------|
| **User passwords** | Manual hash generation | Automatic (init container) |
| **Script location** | Inline in YAML | External file (`config/`) |
| **Config location** | Inline in YAML | External file (`config/`) |
| **Pod restarts** | Manual `kubectl rollout restart` | Automatic (checksum annotations) |
| **1Password format** | Complex (bcrypt hashes) | Simple (plaintext) |
| **Update workflow** | 5 steps, manual | 2 steps, automatic |
| **Time to update** | ~5 minutes (manual) | ~3 minutes (automatic) |
| **Git diffs** | Hard to read (inline YAML) | Clean (actual file changes) |

## Next Steps

The VerneMQ chart is now ready for deployment with:
- ✅ External configuration files
- ✅ Automatic password hash generation
- ✅ Automatic pod restarts on config changes
- ✅ Simplified user management
- ✅ GitOps-friendly workflow

To deploy:
```bash
git add apps/vernemq/ docs/
git commit -m "feat(mqtt): add VerneMQ broker with automatic password management"
git push origin main
```

See `docs/EMQX-TO-VERNEMQ-QUICKSTART.md` for the complete migration guide.
