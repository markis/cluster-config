#!/bin/sh
set -e

echo "Generating vmq.passwd file from user credentials..."

# Clear/Init password file
true >/tmp/vmq.passwd

# Generate SHA-512 hashes using Python (VerneMQ's native format)
python - <<'PYTHON_SCRIPT'
import sys
import hashlib
import secrets
import base64

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

        print(f"Generating SHA-512 hash for user: {username}")

        # Generate random 12-byte salt (VerneMQ default)
        salt = secrets.token_bytes(12)

        # Create SHA-512 hash: sha512(password + salt)
        h = hashlib.sha512()
        h.update(password.encode('utf-8'))
        h.update(salt)
        digest = h.digest()

        # Base64 encode both salt and hash
        salt_b64 = base64.b64encode(salt).decode('utf-8')
        hash_b64 = base64.b64encode(digest).decode('utf-8')

        # VerneMQ format: username:$$<base64_salt>$<base64_hash>
        # Note the double $$ at the start
        with open('/tmp/vmq.passwd', 'a') as out:
            out.write(f"{username}:$${salt_b64}${hash_b64}\n")

print("vmq.passwd file generated successfully")
PYTHON_SCRIPT

# Set ownership to vernemq user (UID 10000)
chown 10000:10000 /tmp/vmq.passwd
chmod 600 /tmp/vmq.passwd
cat /tmp/vmq.passwd
