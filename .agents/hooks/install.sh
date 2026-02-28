#!/bin/sh
# Install agent hooks as git hooks
# This allows both agents and developers to benefit from automated checks

set -e

HOOKS_DIR=".agents/hooks"
GIT_HOOKS_DIR=".git/hooks"

echo "Installing agent hooks as git hooks..."

# Check if we're in a git repository
if [ ! -d ".git" ]; then
  echo "Error: Not in a git repository root"
  exit 1
fi

# Install each hook
for hook in "$HOOKS_DIR"/*; do
  # Skip this install script
  if [ "$(basename "$hook")" = "install.sh" ]; then
    continue
  fi

  # Skip if not a file
  if [ ! -f "$hook" ]; then
    continue
  fi

  hook_name=$(basename "$hook")
  target="$GIT_HOOKS_DIR/$hook_name"

  # Create symlink
  ln -sf "../../$HOOKS_DIR/$hook_name" "$target"
  echo "✓ Installed $hook_name"
done

echo ""
echo "Agent hooks installed successfully!"
echo "These hooks will run automatically for both git commits and agent commits."
