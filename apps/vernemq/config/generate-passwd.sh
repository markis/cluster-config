#!/bin/sh
set -e

echo "Generating vmq.passwd file from user credentials..."

# Clear/Init password file
> /tmp/vmq.passwd

# Use a named pipe for vmq-passwd input
mkfifo /tmp/vmq_pipe || true

# Read users from secret (format: username:password per line)
while IFS=: read -r username password || [ -n "$username" ]; do
  # Skip empty lines and comments
  [ -z "$username" ] && continue
  echo "$username" | grep -q '^#' && continue
  
  # Strip trailing whitespace
  username=$(echo "$username" | xargs)
  password=$(echo "$password" | xargs)
  
  [ -z "$password" ] && continue
  
  echo "Generating hash for user: $username"
  
  # Background process to feed password to vmq-passwd via named pipe
  (
    sleep 0.1
    echo "$password"
    sleep 0.1
    echo "$password"
  ) > /tmp/vmq_pipe &
  
  # Run vmq-passwd with input from named pipe
  if [ ! -f /tmp/vmq.passwd ]; then
    vmq-passwd -c /tmp/vmq.passwd "$username" < /tmp/vmq_pipe || {
      echo "Failed to add user: $username" >&2
      exit 1
    }
  else
    vmq-passwd /tmp/vmq.passwd "$username" < /tmp/vmq_pipe || {
      echo "Failed to add user: $username" >&2
      exit 1
    }
  fi
  
  wait
done < /secrets/users

# Clean up
rm -f /tmp/vmq_pipe

chmod 600 /tmp/vmq.passwd
echo "vmq.passwd file generated successfully"
cat /tmp/vmq.passwd
