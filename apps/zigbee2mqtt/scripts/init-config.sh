#!/bin/sh
set -e

# Install required tools
command -v envsubst >/dev/null 2>&1 || apk add --no-cache gettext
command -v python3 >/dev/null 2>&1 || apk add --no-cache python3 py3-yaml

# Check if configuration.yaml already exists with devices
if [ -f /data/configuration.yaml ] && grep -q "^devices:" /data/configuration.yaml; then
  echo "Configuration file exists with device definitions"
  echo "Merging infrastructure settings from Git with user devices/groups..."

  # Generate new config from template with env vars substituted
  envsubst </config-template/configuration.yaml >/tmp/new-config.yaml

  # Use Python to merge (preserving devices and groups)
  python3 <<'PYTHON_SCRIPT'
import yaml

# Read existing config
with open('/data/configuration.yaml', 'r') as f:
    existing = yaml.safe_load(f)

# Read new template
with open('/tmp/new-config.yaml', 'r') as f:
    new = yaml.safe_load(f)

# Preserve user data
if 'devices' in existing:
    new['devices'] = existing['devices']
if 'groups' in existing:
    new['groups'] = existing['groups']

# Write merged config
with open('/data/configuration.yaml', 'w') as f:
    yaml.dump(new, f, default_flow_style=False, sort_keys=False)
PYTHON_SCRIPT

  echo "Configuration updated: infrastructure from Git, devices/groups preserved"
else
  echo "No existing configuration, initializing from template..."
  envsubst </config-template/configuration.yaml >/data/configuration.yaml
  echo "Configuration initialized"
fi
