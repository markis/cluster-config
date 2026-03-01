#!/bin/sh
set -e

# Install required tools
command -v envsubst >/dev/null 2>&1 || apk add --no-cache gettext

# Generate configuration from template with env vars substituted
echo "Updating configuration from template..."
envsubst </config-template/configuration.yaml >/data/configuration.yaml
echo "Configuration updated"

# Create devices.yaml and groups.yaml if they don't exist
if [ ! -f /data/devices.yaml ]; then
  echo "Creating empty devices.yaml..."
  echo "{}" >/data/devices.yaml
fi

if [ ! -f /data/groups.yaml ]; then
  echo "Creating empty groups.yaml..."
  echo "{}" >/data/groups.yaml
fi

# Note: devices.yaml and groups.yaml are managed separately by Zigbee2MQTT
# and persist on the volume without needing migration
