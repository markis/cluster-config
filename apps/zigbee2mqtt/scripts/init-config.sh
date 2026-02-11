#!/bin/sh
set -e

# Install envsubst if not available (part of gettext package)
command -v envsubst >/dev/null 2>&1 || apk add --no-cache gettext

# Replace environment variables in config and write to data volume
envsubst < /config-template/configuration.yaml > /data/configuration.yaml

echo "Configuration initialized"
cat /data/configuration.yaml
