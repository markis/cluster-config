# Renovate Setup for Auto-Updates

This repository uses Renovate to automatically update container images in Helm charts.

## What It Does

Renovate will:

- Monitor `ghcr.io/markis/hass-dashboard` for new versions
- Monitor `nginx` for new versions
- Update `apps/hass-dashboard/values.yaml` (image tags)
- Update `apps/hass-dashboard/Chart.yaml` (appVersion)
- Create PRs with semantic commit messages (`chore: update hass-dashboard to v2.5.4`)
- **Auto-merge** minor and patch updates
- Require manual approval for major updates

## Setup Instructions

### 1. Enable Renovate on GitHub

1. Go to <https://github.com/apps/renovate>
2. Click "Install" or "Configure"
3. Select your `markis/cluster-config` repository
4. Grant repository access

### 2. Configure Auto-Merge (Optional but Recommended)

To allow Renovate to auto-merge minor/patch updates:

#### Option A: Enable Auto-Merge in GitHub Settings

1. Go to your repo Settings → General
2. Scroll to "Pull Requests"
3. Check "Allow auto-merge"

#### Option B: Use Renovate App Permissions

- The Renovate app will auto-merge if you grant it permission
- This is controlled by the `automerge: true` setting in `renovate.json`

### 3. Test the Configuration

Commit the `renovate.json` file:

```bash
git add renovate.json docs/renovate-setup.md
git commit -m "chore: add Renovate configuration for auto-updates"
git push
```

### 4. First Run

After installation:

1. Renovate will scan your repository
2. It will create an "onboarding" PR to confirm setup
3. Merge the onboarding PR
4. Renovate will then create PRs for any outdated images

## Configuration Details

### Auto-Merge Rules

- **Patch updates** (2.5.3 → 2.5.4): Auto-merged
- **Minor updates** (2.5.x → 2.6.0): Auto-merged
- **Major updates** (2.x.x → 3.0.0): Manual review required

### Commit Format

Renovate follows conventional commits:

```text
chore: update hass-dashboard to v2.5.4
```

This matches your existing commit style from manual updates.

### Rate Limiting

- Max 3 PRs open at once
- Max 2 PRs created per hour
- Prevents overwhelming the repository

## Customization

Edit `renovate.json` to:

- Change auto-merge rules
- Add more apps
- Adjust PR limits
- Change timezone for scheduling

### Adding More Apps

For each app, Renovate automatically detects:

- Docker images in `apps/*/values.yaml`
- Standard Helm chart patterns

For `Chart.yaml` updates, add to `regexManagers`:

```json
{
  "fileMatch": ["^apps/.+/Chart\\.yaml$"],
  "matchStrings": ["appVersion:\\s*[\"']?(?<currentValue>[^\"'\\s]+)[\"']?"],
  "datasourceTemplate": "docker",
  "depNameTemplate": "ghcr.io/owner/app-name"
}
```

## Monitoring

View Renovate activity:

1. Check the "Dependency Graph" tab in your repo
2. Watch for PRs labeled with `renovate`
3. Review the Renovate dashboard at <https://app.renovatebot.com/dashboard>

## Troubleshooting

**Renovate not creating PRs:**

- Check the Renovate logs in the PR comments or dashboard
- Verify the app has permission to create PRs
- Ensure `renovate.json` is valid JSON

**Auto-merge not working:**

- Verify "Allow auto-merge" is enabled in repo settings
- Check that all CI checks pass (if required)
- Ensure branch protection rules allow auto-merge

**Wrong versions detected:**

- Renovate may detect non-semantic versions (sha- tags)
- Our config filters to semantic versions only via datasource detection
- Check the `versioning` field if issues persist

## Alternative: ArgoCD Image Updater

If you prefer ArgoCD-native updates without PRs:

- ArgoCD Image Updater commits directly to git
- Does NOT update `Chart.yaml` `appVersion` field
- Requires additional setup for git write-back
- See: <https://argocd-image-updater.readthedocs.io/>

Renovate is recommended because it handles both files and provides PR-based review.
