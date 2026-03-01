#!/bin/sh
set -e

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

# Check if configuration.yaml already exists with devices
if [ -f /data/configuration.yaml ] && grep -q "^devices:" /data/configuration.yaml; then
  echo "Configuration file exists with device definitions"
  echo "Preserving existing configuration (devices and groups maintained by Zigbee2MQTT)"
  echo "Note: Infrastructure settings are managed in Git. To apply changes, edit values.yaml,"
  echo "      delete configuration.yaml, and restart the pod."
else
  echo "No existing configuration found, initializing from template..."
  cp /config-template/configuration.yaml /data/configuration.yaml
  echo "Configuration initialized"
fi
