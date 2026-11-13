---
type: Runbook
title: GitHub App for repository automation
description: Authenticate automated pull request publishing using short-lived GitHub App installation tokens.
when: Registering or rotating the App that publishes lock-update, Hermes and upstream-cleanup PRs.
resource: .github/workflows/lock-update.yml
tags: [github, actions, automation, security]
---

# GitHub App for repository automation

The scheduled `upstream-watch`, `lock-update`, and `hermes-update` workflows
create or refresh pull requests. GitHub requires approval for PR workflows
created with the job's built-in `GITHUB_TOKEN`. Publish PRs with a dedicated
GitHub App installation token instead. Keep `GITHUB_TOKEN` for ordinary
read-only API access and approved non-PR operations.

## One-time setup

1. Register a GitHub App from [Developer settings](https://github.com/settings/apps/new)
   under the `repparw` account. Suggested name: `repparw-nix-automation`
   (the GitHub App name must be globally unique). Set the homepage to
   `https://github.com/repparw/nix`.
2. Disable the webhook (the app does not receive webhook events), leave
   OAuth user authorization and device flow off, and select **Only on this account**.
3. In **Repository permissions**, grant **Actions: Read and write**,
   **Contents: Read and write**, and **Pull requests: Read and write**.
   Do not grant organization or account permissions. GitHub grants Metadata
   read permission automatically.
4. Install the App under `repparw`. Select **Only select repositories**,
   then `repparw/nix`, not **All repositories**.
5. In the App's General settings, generate a private key (`.pem`) and copy
   the **Client ID**. Do not commit or upload the private key to this repo.
6. Configure repository Actions secrets/variables:
   - [Variable](https://github.com/repparw/nix/settings/variables/actions):
     `GH_AUTOMATION_APP_CLIENT_ID` = the App's Client ID
   - [Secret](https://github.com/repparw/nix/settings/secrets/actions):
     `GH_AUTOMATION_APP_PRIVATE_KEY` = the *entire* PEM private key,
     including the BEGIN/END lines and newlines.

Do not store an installation token as a secret. GitHub App installation tokens
expire after one hour; `actions/create-github-app-token` creates a new one for
each job and revokes it at job completion.

The token action defaults to **the current repository only** when `owner`
and `repositories` are omitted. The installation is independently limited
to the same repo. Its outputs provide the token for Git operations and PR API
calls, and the app's permission grants are explicitly narrowed in each step.

## Validation

After merging the authentication workflow changes and configuring the App:

1. Run `upstream-watch` manually. Readiness and notification-only activity
   should work even without a publishable cleanup. When a cleanup becomes ready,
   it must produce an App-authored PR and regular `pull_request` checks without
   a workflow approval prompt.
2. Trigger `lock-update` and `hermes-update` through their manual
   `workflow_dispatch` events when their normal candidate conditions are met.
   Observe exact-SHA CI, PR checks, and the existing merge policy.
   Hermes updates remain **manual merge** by design.
3. Verify the commit branch and PR actor is the App bot, and that a follow-up
   branch refresh triggers CI without manual approval.

A missing App ID/private key must **fail the publishing workflow** rather than
silently use `GITHUB_TOKEN`. Notification-only upstream readiness can still
use the built-in token. Existing approval-gated PR runs are not automatically
unblocked by changing credentials for future publishes.

## Rotation and recovery

Generate a second private key in the App settings, replace the repository
secret, exercise one workflow, then revoke the older key. If the App is
uninstalled or loses permissions, publishing will fail closed. Do not disable
required CI checks as a workaround. Exact-SHA and provenance checks remain
independent of authentication.
