#!/bin/sh
set -e

# Install required tools
command -v envsubst >/dev/null 2>&1 || apk add --no-cache gettext

# Generate configuration from template with env vars substituted
echo "Updating configuration from template..."
envsubst </config-template/configuration.yaml >/data/configuration.yaml
echo "Configuration updated"

# Note: devices.yaml and groups.yaml are managed separately by Zigbee2MQTT
# and persist on the volume without needing migration
