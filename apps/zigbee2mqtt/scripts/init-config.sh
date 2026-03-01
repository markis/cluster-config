#!/bin/sh
set -e

# Install envsubst if not available
command -v envsubst >/dev/null 2>&1 || apk add --no-cache gettext

# Check if configuration.yaml already exists and has device/group definitions
if [ -f /data/configuration.yaml ] && grep -q "^devices:" /data/configuration.yaml; then
  echo "Configuration file exists with device definitions, preserving it..."
  echo "Note: To regenerate config, delete /data/configuration.yaml and restart the pod"
else
  echo "Initializing configuration from template..."
  envsubst </config-template/configuration.yaml >/data/configuration.yaml
  echo "Configuration initialized"
fi
