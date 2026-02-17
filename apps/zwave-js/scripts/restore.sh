#!/bin/sh
set -e

if [ -z "$BACKUP_FILE" ]; then
  echo "ERROR: BACKUP_FILE environment variable must be set"
  echo "Example: BACKUP_FILE=zwave-js-20260216-030000.tar.gz"
  exit 1
fi

apk add --no-cache openssh-client

# Create SSH directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Add SSH key from secret
echo "$SSH_PRIVATE_KEY" >~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa

# Disable host key checking for internal network
echo "StrictHostKeyChecking no" >~/.ssh/config

# Download backup from destination
echo "Downloading backup: ${BACKUP_FILE}"
scp -i ~/.ssh/id_rsa \
  "${BACKUP_USER}@${BACKUP_HOST}:${BACKUP_PATH}/${BACKUP_FILE}" \
  "/tmp/${BACKUP_FILE}"

# Clear existing data (be careful!)
echo "Clearing existing data..."
rm -rf /store/*

# Extract backup
echo "Restoring backup..."
tar xzf "/tmp/${BACKUP_FILE}" -C /store

echo "Restore completed successfully"
echo "You can now restart the zwave-js StatefulSet"
