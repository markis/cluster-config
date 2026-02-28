#!/bin/bash
set -euo pipefail

echo "Generating vmq.passwd file from user credentials..."

# Clear/Init password file
> /tmp/vmq.passwd

# Read users from secret (format: username:password per line)
while IFS=: read -r username password || [ -n "$username" ]; do
  # Skip empty lines and comments
  [ -z "$username" ] && continue
  echo "$username" | grep -q '^#' && continue
  
  # Strip trailing whitespace/newlines
  username=$(echo "$username" | tr -d '\n\r' | xargs)
  password=$(echo "$password" | tr -d '\n\r')
  
  echo "Generating hash for user: $username"
  # Use vmq-passwd with carriage returns (interactive mode simulation)
  printf "%s\r%s\r" "$password" "$password" | vmq-passwd -c /tmp/vmq.passwd "$username" || {
    echo "Failed to add user: $username" >&2
    exit 1
  }
done < /secrets/users

chmod 600 /tmp/vmq.passwd
echo "vmq.passwd file generated successfully"
cat /tmp/vmq.passwd
