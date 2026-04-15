# Hermes Agent Setup Guide

This guide walks you through setting up Hermes Agent with OpenCode Go and Discord integration.

## Prerequisites

- OpenCode Go API key
- Discord bot created (see steps below)
- 1Password CLI access to k8s-secrets vault

## Step 1: Create Discord Bot

1. Go to <https://discord.com/developers/applications>
2. Click "New Application" → Name it "Hermes Agent" → Create
3. Navigate to **Bot** section → Click "Create Bot"
4. Enable these **Privileged Gateway Intents**:
   - ✅ **Message Content Intent** (critical!)
   - ✅ **Server Members Intent** (critical!)
5. Click "Reset Token" → Copy and save the token

## Step 2: Get Your Discord User ID

1. In Discord: Settings → Advanced → Enable **Developer Mode**
2. Right-click your username anywhere → **Copy User ID**
3. Save this number (e.g., `284102345871466496`)

## Step 3: Invite Bot to Your Server

1. In Developer Portal → **Installation** tab
2. Enable "Guild Install" → Select "Discord Provided Link"
3. Under Default Install Settings:
   - **Scopes**: `bot` and `applications.commands`
   - **Permissions**: Select these:
     - View Channels
     - Send Messages
     - Embed Links
     - Attach Files
     - Read Message History
     - Send Messages in Threads
     - Add Reactions
4. Use the generated link to invite the bot

**Shortcut URL format:**

```text
https://discord.com/oauth2/authorize?client_id=YOUR_APP_ID&scope=bot+applications.commands&permissions=274878286912
```

## Step 4: Configure 1Password Secrets

Create/update the item at `vaults/k8s-secrets/items/hermes-agent`:

### Required Fields

| Field Name | Value | Description |
|------------|-------|-------------|
| `OPENCODE_GO_API_KEY` | Your OpenCode Go API key | Native OpenCode Go provider |
| `DISCORD_BOT_TOKEN` | Discord bot token | From Step 1 |
| `DISCORD_ALLOWED_USERS` | `284102345871466496` | Your Discord User ID from Step 2 |

### Backup Configuration (Restic - SFTP)

| Field Name | Example | Description |
|------------|---------|-------------|
| `RESTIC_REPOSITORY` | `sftp:backup@backup.markis.network:/backups/hermes-agent` | SFTP repository URL |
| `RESTIC_PASSWORD` | `<strong-password>` | Repository encryption password |
| `SSH_PRIVATE_KEY` | `-----BEGIN OPENSSH PRIVATE KEY-----...` | SSH key for SFTP (Ed25519 PEM format) |

### Optional Fields

| Field Name | Example | Description |
|------------|---------|-------------|
| `DISCORD_HOME_CHANNEL` | `1234567890` | Channel ID for cron/notifications |
| `FIRECRAWL_API_KEY` | `fc-...` | For web scraping |
| `FAL_KEY` | `...` | For image generation |

## Step 5: Deploy to Kubernetes

```bash
# Verify the chart is valid
helm lint apps/hermes-agent --strict

# Template the chart to see what will be deployed
helm template apps/hermes-agent --debug

# Commit and push to deploy via ArgoCD
git add apps/hermes-agent/
git commit -m "Add hermes-agent with OpenCode Go and Discord"
git push
```

## Step 6: Verify Deployment

```bash
# Check pod status
kubectl get pods -n hermes-agent

# View logs
kubectl logs -n hermes-agent deployment/hermes-agent -f

# Check if bot came online in Discord
# The bot should appear in your server's member list
```

## Using the Bot

### Direct Messages (DMs)

- Simply message the bot - no @mention required
- Each DM is a separate conversation

### Server Channels

- **Requires @mention**: `@Hermes Agent what time is it?`
- **Auto-threads**: Bot creates a new thread for each conversation
- **No mention needed in threads**: Once thread is created, just reply

### Useful Commands

```text
/new              - Start fresh conversation
/model            - Show/change AI model
/status           - Show session info
/stop             - Stop current task
/voice tts        - Toggle spoken replies
/background <prompt> - Run task in background
/help             - Show all commands
```

### Tool Progress

The bot sends progress updates as it works:

- 💻 Running terminal commands
- 🔍 Searching the web
- 📄 Reading files
- 🐍 Executing code

Control verbosity with `/verbose` (cycles: off → new → all → verbose)

## Troubleshooting

### Bot is online but doesn't respond

**Problem**: Message Content Intent is disabled

**Fix**:

1. Go to Discord Developer Portal → Your App → Bot
2. Scroll to "Privileged Gateway Intents"
3. Enable **Message Content Intent**
4. Save and restart the pod: `kubectl rollout restart deployment/hermes-agent -n hermes-agent`

### "User not allowed" error

**Problem**: Your Discord User ID isn't in `DISCORD_ALLOWED_USERS`

**Fix**:

1. Update 1Password item with your correct User ID
2. Wait for 1Password Operator to sync (~1 minute)
3. Restart pod: `kubectl rollout restart deployment/hermes-agent -n hermes-agent`

### Bot doesn't see messages in a channel

**Problem**: Bot lacks channel permissions

**Fix**:

1. Right-click channel → Edit Channel → Permissions
2. Add the bot's role with "View Channel" and "Read Message History"

### Context sharing between users

**Problem**: Multiple users in the same channel sharing conversation history

**Fix**: This is normal with `group_sessions_per_user: true` (default). Each user gets their own isolated
session even in shared channels.

To make a channel truly collaborative (one shared conversation), set in `config.yaml`:

```yaml
group_sessions_per_user: false
```

## Configuration Reference

### OpenCode Go Settings

```yaml
model:
  provider: opencode-go
  model: claude-sonnet-4-5
```

The `OPENCODE_GO_API_KEY` environment variable is used for authentication. OpenCode Go is a natively
supported provider in Hermes Agent.

### Discord Settings

```yaml
discord:
  require_mention: true      # Require @mention in channels
  auto_thread: true         # Create threads automatically
  reactions: true           # Add emoji reactions
  free_response_channels: [] # Channel IDs that don't need @mention
  ignored_channels: []      # Channel IDs where bot never responds
```

### Session Isolation

```yaml
group_sessions_per_user: true  # Isolate sessions per user in shared channels
```

## Next Steps

- [Hermes Agent Documentation](https://hermes-agent.nousresearch.com/docs/)
- [Discord Setup Guide](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord)
- [Voice Mode Guide](https://hermes-agent.nousresearch.com/docs/user-guide/features/voice-mode)
- [Skills Documentation](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills)
