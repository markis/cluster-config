#!/bin/sh
set -e

apk add --no-cache openssh-client

# Create SSH directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add SSH key from secret
echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa

# Disable host key checking for internal network
echo "StrictHostKeyChecking no" > ~/.ssh/config

# Create backup with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="zigbee2mqtt-${TIMESTAMP}.tar.gz"

echo "Creating backup: ${BACKUP_NAME}"
tar czf "/tmp/${BACKUP_NAME}" -C /data .

# Ensure backup directory exists on remote
ssh -i ~/.ssh/id_rsa "root@${BACKUP_HOST}" \
  "mkdir -p ${BACKUP_PATH}"

# Copy backup to destination
echo "Uploading backup to ${BACKUP_HOST}:${BACKUP_PATH}"
scp -i ~/.ssh/id_rsa "/tmp/${BACKUP_NAME}" \
  "root@${BACKUP_HOST}:${BACKUP_PATH}/"

# Cleanup old backups (keep last N)
echo "Cleaning up old backups (keeping last ${BACKUP_RETENTION})"
ssh -i ~/.ssh/id_rsa "root@${BACKUP_HOST}" \
  "cd ${BACKUP_PATH} && ls -t zigbee2mqtt-*.tar.gz | tail -n +$((BACKUP_RETENTION + 1)) | xargs -r rm"

echo "Backup completed successfully"
