#!/bin/sh
set -e

# Install required tools
command -v python3 >/dev/null 2>&1 || apk add --no-cache python3 py3-yaml

# Generate secret.yaml from Kubernetes secrets (always regenerate)
cat >/data/secret.yaml <<EOF
# Secrets managed by Kubernetes - regenerated on every pod restart
mqtt_username: ${MQTT_USERNAME}
mqtt_password: ${MQTT_PASSWORD}
zigbee_pan_id: ${ZIGBEE_PAN_ID}
zigbee_ext_pan_id: ${ZIGBEE_EXT_PAN_ID}
zigbee_network_key: ${ZIGBEE_NETWORK_KEY}
EOF

echo "Generated secret.yaml from Kubernetes secrets"

# Check if configuration.yaml already exists
if [ -f /data/configuration.yaml ] && grep -q "^devices:" /data/configuration.yaml; then
  echo "Configuration file exists with device definitions"
  echo "Merging infrastructure settings from template with existing devices/groups..."

  # Use Python to merge YAML files (preserving devices and groups from old config)
  python3 <<'PYTHON_SCRIPT'
import yaml
import sys

# Read existing config (has devices/groups)
with open('/data/configuration.yaml', 'r') as f:
    existing_config = yaml.safe_load(f)

# Read new template config (has updated infrastructure settings)
with open('/config-template/configuration.yaml', 'r') as f:
    new_config = yaml.safe_load(f)

# Preserve devices and groups from existing config
if 'devices' in existing_config:
    new_config['devices'] = existing_config['devices']
if 'groups' in existing_config:
    new_config['groups'] = existing_config['groups']

# Write merged config
with open('/data/configuration.yaml', 'w') as f:
    yaml.dump(new_config, f, default_flow_style=False, sort_keys=False)

print("Configuration updated: infrastructure from template, devices/groups preserved")
PYTHON_SCRIPT

else
  echo "No existing configuration found, initializing from template..."
  cp /config-template/configuration.yaml /data/configuration.yaml
  echo "Configuration initialized"
fi
