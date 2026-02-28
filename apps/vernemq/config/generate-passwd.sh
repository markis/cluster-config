#!/bin/sh
set -e

echo "Generating vmq.passwd file from user credentials..."

# Install Python and bcrypt if not present
apk add --no-cache python3 py3-pip >/dev/null 2>&1 || true
pip3 install --quiet bcrypt 2>/dev/null || true

# Clear/Init password file
> /tmp/vmq.passwd

# Generate bcrypt hashes using Python
python3 - <<'PYTHON_SCRIPT'
import sys
import bcrypt

with open('/secrets/users', 'r') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        
        if ':' not in line:
            continue
            
        username, password = line.split(':', 1)
        username = username.strip()
        password = password.strip()
        
        if not username or not password:
            continue
        
        print(f"Generating bcrypt hash for user: {username}")
        
        # Generate bcrypt hash (cost factor 12, standard for VerneMQ)
        hashed = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt(rounds=12))
        hash_str = hashed.decode('utf-8')
        
        # Write to password file
        with open('/tmp/vmq.passwd', 'a') as out:
            out.write(f"{username}:{hash_str}\n")

print("vmq.passwd file generated successfully")
PYTHON_SCRIPT

chmod 600 /tmp/vmq.passwd
cat /tmp/vmq.passwd
