# Hermes Agent

Hermes Agent is a self-improving AI agent built by [Nous Research](https://nousresearch.com). It features a
built-in learning loop with skills creation, memory management, and multi-platform messaging support.

## Features

- **Self-improving**: Creates and improves skills from experience
- **Persistent memory**: Cross-session recall with FTS5 search
- **Multi-platform**: Telegram, Discord, Slack, WhatsApp support
- **Scheduled automations**: Built-in cron scheduler
- **Delegation**: Spawn isolated subagents for parallel work

## Configuration

This deployment uses **OpenCode Go** as the AI provider and **Discord** as the messaging platform.

### Required Secrets (1Password)

Create a 1Password item at `vaults/k8s-secrets/items/hermes-agent` with the following fields:

#### Required

- `OPENCODE_GO_API_KEY` - OpenCode Go API key
- `DISCORD_BOT_TOKEN` - Discord bot token from the Discord Developer Portal
- `DISCORD_ALLOWED_USERS` - Comma-separated Discord user IDs allowed to interact with the bot

#### Backup & Restore (Restic - SFTP)

- `RESTIC_REPOSITORY` - Restic repository URL (e.g., `sftp:user@host:/path/to/backups/hermes-agent`)
- `RESTIC_PASSWORD` - Restic repository encryption password
- `SSH_PRIVATE_KEY` - SSH private key for SFTP authentication (PEM format)

#### Optional

- `DISCORD_HOME_CHANNEL` - Channel ID for proactive messages (cron jobs, notifications)
- `FIRECRAWL_API_KEY` - For web search and scraping
- `FAL_KEY` - For image generation (FLUX)

### Values Configuration

Edit `values.yaml` to customize:

```yaml
image:
  repository: nousresearch/hermes-agent
  tag: "latest"

deployment:
  resources:
    requests:
      memory: "2Gi"  # Minimum for browser tools
      cpu: "500m"
    limits:
      memory: "4Gi"
      cpu: "2000m"

ingress:
  host: hermes.markis.network  # External hostname
```

### Config File

The default configuration in `files/config.yaml` is pre-configured with:

- **AI Provider**: OpenCode Go (native support via `opencode-go` provider)
- **Model**: `claude-sonnet-4-5`
- **Gateway**: Discord enabled (Telegram/Slack disabled)
- **Discord Settings**:
  - Requires @mention in server channels
  - Auto-creates threads on @mention
  - Adds emoji reactions for progress
- **Session Isolation**: Per-user sessions in shared channels
- **Memory**: Enabled with 100k token limit
- **Skills**: Auto-create and auto-improve enabled

### Discord Bot Setup

Before deploying, you need to create a Discord bot and get the required credentials:

1. **Create Discord Application**
   - Go to [Discord Developer Portal](https://discord.com/developers/applications)
   - Click "New Application" and give it a name
   - Navigate to "Bot" section and create a bot

2. **Enable Required Intents**
   - In the Bot section, scroll to "Privileged Gateway Intents"
   - Enable **Message Content Intent** (required to read messages)
   - Enable **Server Members Intent** (required for user authorization)

3. **Get Bot Token**
   - Still in the Bot section, click "Reset Token"
   - Copy the token and save it to 1Password as `DISCORD_BOT_TOKEN`

4. **Get Your User ID**
   - In Discord, go to Settings → Advanced → Enable Developer Mode
   - Right-click your username → Copy User ID
   - Save this to 1Password as `DISCORD_ALLOWED_USERS`

5. **Invite Bot to Server**
   - In Developer Portal, go to Installation tab
   - Enable "Guild Install" and select "Discord Provided Link"
   - Scopes: `bot` and `applications.commands`
   - Permissions: `274878286912` (View Channels, Send Messages, Embed Links, Attach Files, Read Message
     History, Send Messages in Threads, Add Reactions)
   - Use the generated link to invite the bot to your server

For full setup instructions, see the [Discord Setup Guide](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord).

## Architecture

- **Main Container**: `nousresearch/hermes-agent:latest` - Runs the agent in gateway mode
- **Restic Sidecar**: `restic/restic:latest` - Backs up `/opt/data` every 15 minutes
- **Data Volume**: `/opt/data` (emptyDir shared between containers)
- **Shared Memory**: `/dev/shm` (1Gi for browser automation)
- **Init Containers**:
  1. **restore-backup** - Restores latest restic snapshot before startup
  2. **setup-config** - Copies default config if not present in backup

### Backup Strategy

The deployment uses a **restic sidecar pattern** to maintain state without a PVC:

- **Init Container**: Restores the latest snapshot from restic before Hermes starts
- **Sidecar Container**: Backs up `/opt/data` to remote storage every 15 minutes
- **Retention Policy**: Keeps last 48 backups (12 hours), last 7 daily, last 4 weekly
- **Excludes**: Temporary files (logs, image cache, audio cache)
- **Shared emptyDir**: Both Hermes and restic mount the same volume

This approach provides restart survival without Kubernetes PVCs, with backup orchestration independent of the Hermes process.

## Resources

- **Memory**: 2-4 GB (browser automation is memory-intensive)
- **CPU**: 500m-2000m
- **Shared memory**: 1 GB for Playwright/Chromium

## Health Checks

- **Liveness probe**: `hermes status` every 30s
- **Readiness probe**: `hermes status` every 10s

## Documentation

- [Official Docs](https://hermes-agent.nousresearch.com/docs/)
- [GitHub](https://github.com/NousResearch/hermes-agent)
- [Discord](https://discord.gg/NousResearch)

## Deployment

The application is automatically deployed via ArgoCD when changes are pushed to the main branch.

```bash
# Validate the chart
helm lint apps/hermes-agent --strict

# Template the chart
helm template apps/hermes-agent --debug

# Check rendered manifests
helm template apps/hermes-agent | kubeconform -strict
```

## Backup & Restore

### SFTP Backend Configuration

This deployment uses SFTP for restic backups, matching the zeroclaw pattern:

```bash
# Example SFTP backend setup
RESTIC_REPOSITORY=sftp:backup-user@backup.markis.network:/backups/hermes-agent
RESTIC_PASSWORD=<strong-encryption-password>
SSH_PRIVATE_KEY=<ed25519-private-key-pem>

# The repository is automatically initialized on first run
# Both init container and sidecar use: restic init || true
```

**SSH Key Format**: The `SSH_PRIVATE_KEY` should be in PEM format (Ed25519 recommended):

```text
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
...
-----END OPENSSH PRIVATE KEY-----
```

### Manual Restore

To restore to a specific snapshot:

```bash
# List snapshots
kubectl exec -n hermes-agent deployment/hermes-agent -c restic-backup -- \
  restic snapshots

# Restore a specific snapshot
kubectl exec -n hermes-agent deployment/hermes-agent -c restore-backup -- \
  restic restore <snapshot-id> --target /opt/data
```

### Backup Monitoring

```bash
# View backup logs
kubectl logs -n hermes-agent deployment/hermes-agent -c restic-backup -f

# Check latest snapshots
kubectl exec -n hermes-agent deployment/hermes-agent -c restic-backup -- \
  restic snapshots --latest 5
```

## Notes

- State persists across pod restarts via restic backups (every 15 minutes)
- No PVC required - uses emptyDir with external backup storage
- Backup orchestration is independent of Hermes process (survives crashes)
- First startup with no existing backups will create a fresh Hermes installation
- Browser tools require shared memory (`/dev/shm`) for Playwright
