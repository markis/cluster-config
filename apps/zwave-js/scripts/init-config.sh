#!/bin/sh
set -e

# Install envsubst if not available (part of gettext package)
command -v envsubst >/dev/null 2>&1 || apk add --no-cache gettext

# Replace environment variables in config and write to store volume
envsubst </config-template/settings.json >/store/settings.json

echo "Configuration initialized"
cat /store/settings.json
