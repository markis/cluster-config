#!/bin/sh
set -e

echo "Generating vmq.passwd file from user credentials..."

# Read users from secret (format: username:password per line)
while IFS=: read -r username password || [ -n "$username" ]; do
  # Skip empty lines and comments
  [ -z "$username" ] && continue
  echo "$username" | grep -q '^#' && continue
  
  echo "Generating hash for user: $username"
  # Use vmq-passwd to generate bcrypt hash
  echo "$password" | vmq-passwd -c /tmp/vmq.passwd "$username"
done < /secrets/users

echo "vmq.passwd file generated successfully"
cat /tmp/vmq.passwd
