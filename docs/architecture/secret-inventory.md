---
type: Architecture Concept
when: Read when adding, consuming, rotating, or documenting SOPS secrets.
title: Secret Inventory and Management
description: Inventory and operating rules for encrypted values, consumers, and deployment scope.
resource: secrets
tags: [security, secrets, sops-nix]
---

# Secret Inventory and Management

This file contains names and deployment metadata only. Never add secret values.

Secret material belongs in consumer-scoped `*.sops.yaml` files under `secrets/`
and is managed through `sops-nix`. Each service or aspect declares its own
`sopsFile`, limiting the ciphertext and recipient blast radius.

| SOPS file | Secret | Purpose | Consumer | Hosts |
| --- | --- | --- | --- | --- |
| `secrets/nix.sops.yaml` | `accessTokens` | Authenticate Nix fetches against private sources | Nix daemon configuration | `alpha` |
| `secrets/backup.sops.yaml` | `resticPassword` | Unlock the encrypted Restic repository | Restic backup | `alpha`, `pi` |
| `secrets/rclone.sops.yaml` | `rcloneDriveId` | Identify the Google Drive OAuth client | rclone Home Manager services | `alpha`, `pi` |
| `secrets/rclone.sops.yaml` | `rcloneDriveToken` | Authorize Google Drive access | rclone Home Manager services | `alpha`, `pi` |
| `secrets/rclone.sops.yaml` | `rcloneDriveSecret` | Authenticate the Google Drive OAuth client | rclone Home Manager services | `alpha`, `pi` |
| `secrets/rclone.sops.yaml` | `rcloneCrypt` | Unlock the encrypted rclone remote | rclone Home Manager services | `alpha`, `pi` |
| `secrets/rclone.sops.yaml` | `rcloneObsidianCrypt` | Unlock the Remotely Save-compatible Obsidian crypt remote | Obsidian bisync service | `alpha` |
| `secrets/rclone.sops.yaml` | `rcloneClarodrive` | Authenticate the Claro Drive remote | rclone Home Manager services | `alpha`, `pi` |
| `secrets/rclone.sops.yaml` | `rcloneDropbox` | Authorize Dropbox access | rclone Home Manager services | `alpha`, `pi` |
| `secrets/rclone.sops.yaml` | `rcloneNextcloud` | Authenticate the Nextcloud remote | rclone Home Manager services | `alpha`, `pi` |
| `secrets/proxy.sops.yaml` | `cloudflare` | Authorize Cloudflare DNS-01 certificate updates | Traefik | `alpha`, `pi` |
| `secrets/proxy.sops.yaml` | `qbittorrentAuth` | Configure qBittorrent proxy authentication | Traefik | `alpha`, `pi` |
| `secrets/ddclient.sops.yaml` | `ddclientPassword` | Authorize dynamic DNS updates | ddclient | `alpha`, `pi` |
| `secrets/authelia.sops.yaml` | `authelia/jwtSecret` | Sign Authelia identity-verification tokens | Authelia | `alpha`, `pi` |
| `secrets/authelia.sops.yaml` | `authelia/oidcHmacSecret` | Protect Authelia OIDC authorization data | Authelia | `alpha`, `pi` |
| `secrets/authelia.sops.yaml` | `authelia/oidcJwksKey` | Sign Authelia OIDC tokens | Authelia | `alpha`, `pi` |
| `secrets/authelia.sops.yaml` | `authelia/sessionSecret` | Encrypt and authenticate Authelia sessions | Authelia | `alpha`, `pi` |
| `secrets/authelia.sops.yaml` | `authelia/smtpPassword` | Authenticate Authelia to its SMTP relay | Authelia | `alpha`, `pi` |
| `secrets/authelia.sops.yaml` | `authelia/storageEncryptionKey` | Encrypt sensitive Authelia storage fields | Authelia | `alpha`, `pi` |
| `secrets/archisteamfarm.sops.yaml` | `steamPassword` | Authenticate the managed Steam account | ArchiSteamFarm | `pi` |
| `secrets/jellyfin.sops.yaml` | `jellyfinBackupKey` | Authorize Jellyfin backup creation | Jellyfin backup tooling | `alpha` |
| `secrets/automations.sops.yaml` | `discordWebhook` | Deliver automation notifications to Discord | Automation services | `pi` |
| `secrets/matriz.sops.yaml` | `matrizApiUsername` | Identify the EcoValores Matriz API user without publishing its CUIT | Matriz account snapshot service | `alpha` |
| `secrets/matriz.sops.yaml` | `matrizApiPassword` | Authenticate the local EcoValores Matriz adapter | Matriz account snapshot service | `alpha` |
| `secrets/matriz.sops.yaml` | `matrizApiAccount` | Select the EcoValores Matriz account without publishing its identifier | Matriz account snapshot service | `alpha` |
| `secrets/hermes.sops.yaml` | `hermes-env` | Seed `$HERMES_HOME/.env` for the Hermes gateway (chat platform tokens, LLM API keys) | `services.hermes-agent` environmentFiles | `pi` |
| `secrets/ieb.sops.yaml` | `iebUsername` | Identify the IEB API user | IEB API adapter (`ieb-api` aspect) | `alpha` |
| `secrets/ieb.sops.yaml` | `iebPassword` | Authenticate the IEB API user | IEB API adapter (`ieb-api` aspect) | `alpha` |
The creation rule grants each host's SSH host-key recipient plus the personal
recovery recipient. Files carry only the recipients their consumers need:
files for services that run on both hosts (`proxy`, `ddclient`, `authelia`,
`backup`, `rclone`, `archisteamfarm`, `automations`) include pi's recipient
(`age1x7qu0en7rg0qm6rq5dfvyn3w34se2qt6wdw7yzgtwjkgj3skssgqmeut5m`, derived
from its preserved Debian-era host key), while files for alpha-only services
(`ieb`, `jellyfin`, `matriz`) do not. New consumers on pi therefore need a
recipient added to any file that lacks it. Add a recipient only when
introducing a genuinely new key, then run `sops updatekeys` on the affected
files.

NixOS decrypts with the machine SSH host key at
`/etc/ssh/ssh_host_ed25519_key`; the personal Age recipient in `.sops.yaml` is
recovery access and is not used during activation. Docs, plans, and commits
should refer to SOPS secret names or source modules, never secret values.

## Source

- `modules/aspects/secrets.nix`
- `secrets/`

## Related

- [Repository layout](repository-layout.md)
