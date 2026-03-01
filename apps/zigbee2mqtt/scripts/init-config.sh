#!/bin/sh
set -e

# Install envsubst and yq if not available
command -v envsubst >/dev/null 2>&1 || apk add --no-cache gettext
command -v yq >/dev/null 2>&1 || apk add --no-cache yq

# Check if configuration.yaml already exists
if [ -f /data/configuration.yaml ]; then
  echo "Configuration file exists, updating only infrastructure settings..."

  # Generate temporary config from template with env vars substituted
  envsubst </config-template/configuration.yaml >/tmp/new-config.yaml

  # Update only infrastructure-related settings (preserve devices and groups)
  # Extract current devices and groups sections
  yq eval '.devices' /data/configuration.yaml >/tmp/devices.yaml
  yq eval '.groups' /data/configuration.yaml >/tmp/groups.yaml

  # Use new template as base, then merge back devices and groups
  cp /tmp/new-config.yaml /data/configuration.yaml

  # Only restore devices/groups if they existed in old config
  if [ -s /tmp/devices.yaml ] && [ "$(cat /tmp/devices.yaml)" != "null" ]; then
    yq eval-all 'select(fileIndex == 0) * {"devices": select(fileIndex == 1)}' \
      /data/configuration.yaml /tmp/devices.yaml >/tmp/merged.yaml
    mv /tmp/merged.yaml /data/configuration.yaml
  fi

  if [ -s /tmp/groups.yaml ] && [ "$(cat /tmp/groups.yaml)" != "null" ]; then
    yq eval-all 'select(fileIndex == 0) * {"groups": select(fileIndex == 1)}' \
      /data/configuration.yaml /tmp/groups.yaml >/tmp/merged.yaml
    mv /tmp/merged.yaml /data/configuration.yaml
  fi

  echo "Configuration updated (devices and groups preserved)"
else
  echo "No existing configuration found, initializing from template..."
  envsubst </config-template/configuration.yaml >/data/configuration.yaml
  echo "Configuration initialized"
fi
