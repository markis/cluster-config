#!/bin/sh
set -e

# Replace environment variables in config and write to data volume
cat /config-template/configuration.yaml | \
  sed "s/\${MQTT_USERNAME}/$MQTT_USERNAME/g" | \
  sed "s/\${MQTT_PASSWORD}/$MQTT_PASSWORD/g" | \
  sed "s/\${ZIGBEE_PAN_ID}/$ZIGBEE_PAN_ID/g" | \
  sed "s/\${ZIGBEE_EXT_PAN_ID}/$ZIGBEE_EXT_PAN_ID/g" | \
  sed "s/\${ZIGBEE_NETWORK_KEY}/$ZIGBEE_NETWORK_KEY/g" \
  > /data/configuration.yaml

echo "Configuration initialized"
cat /data/configuration.yaml
