---
type: Architecture Concept
title: Secret Inventory
description: Non-secret inventory of encrypted values, consumers, and deployment scope.
resource: secrets
tags: [security, secrets, sops-nix]
---

# Secret Inventory

This file contains names and deployment metadata only. Never add secret values.

| SOPS file | Secret | Purpose | Consumer | Hosts |
| --- | --- | --- | --- | --- |
| `secrets/nix.sops.yaml` | `accessTokens` | Authenticate Nix fetches against private sources | Nix daemon configuration | `alpha` |
| `secrets/backup.sops.yaml` | `resticPassword` | Unlock the encrypted Restic repository | Restic backup | `alpha` |
| `secrets/rclone.sops.yaml` | `rcloneDriveId` | Identify the Google Drive OAuth client | rclone Home Manager services | `alpha` |
| `secrets/rclone.sops.yaml` | `rcloneDriveToken` | Authorize Google Drive access | rclone Home Manager services | `alpha` |
| `secrets/rclone.sops.yaml` | `rcloneDriveSecret` | Authenticate the Google Drive OAuth client | rclone Home Manager services | `alpha` |
| `secrets/rclone.sops.yaml` | `rcloneCrypt` | Unlock the encrypted rclone remote | rclone Home Manager services | `alpha` |
| `secrets/rclone.sops.yaml` | `rcloneClarodrive` | Authenticate the Claro Drive remote | rclone Home Manager services | `alpha` |
| `secrets/rclone.sops.yaml` | `rcloneDropbox` | Authorize Dropbox access | rclone Home Manager services | `alpha` |
| `secrets/rclone.sops.yaml` | `rcloneNextcloud` | Authenticate the Nextcloud remote | rclone Home Manager services | `alpha` |
| `secrets/proxy.sops.yaml` | `cloudflare` | Authorize Cloudflare DNS-01 certificate updates | Traefik | `alpha` |
| `secrets/proxy.sops.yaml` | `qbittorrentAuth` | Configure qBittorrent proxy authentication | Traefik | `alpha` |
| `secrets/ddclient.sops.yaml` | `ddclientPassword` | Authorize dynamic DNS updates | ddclient | `alpha` |
| `secrets/authelia.sops.yaml` | `authelia/jwtSecret` | Sign Authelia identity-verification tokens | Authelia | `alpha` |
| `secrets/authelia.sops.yaml` | `authelia/oidcHmacSecret` | Protect Authelia OIDC authorization data | Authelia | `alpha` |
| `secrets/authelia.sops.yaml` | `authelia/oidcJwksKey` | Sign Authelia OIDC tokens | Authelia | `alpha` |
| `secrets/authelia.sops.yaml` | `authelia/sessionSecret` | Encrypt and authenticate Authelia sessions | Authelia | `alpha` |
| `secrets/authelia.sops.yaml` | `authelia/smtpPassword` | Authenticate Authelia to its SMTP relay | Authelia | `alpha` |
| `secrets/authelia.sops.yaml` | `authelia/storageEncryptionKey` | Encrypt sensitive Authelia storage fields | Authelia | `alpha` |
| `secrets/archisteamfarm.sops.yaml` | `steamPassword` | Authenticate the managed Steam account | ArchiSteamFarm | `alpha` |
| `secrets/jellyfin.sops.yaml` | `jellyfinBackupKey` | Authorize Jellyfin backup creation | Jellyfin backup tooling | `alpha` |
| `secrets/automations.sops.yaml` | `discordWebhook` | Deliver automation notifications to Discord | Automation services | `alpha` |
| `secrets/streaming.sops.yaml` | `sunshineApiUsername` | Authenticate Sunshine API health checks | Sunshine watchdog | `alpha` |
| `secrets/streaming.sops.yaml` | `sunshineApiPassword` | Authenticate Sunshine API health checks | Sunshine watchdog | `alpha` |
The creation rule grants `alpha` only its SSH host-key recipient plus the
recovery recipient. Add a host recipient to only the files that host consumes,
then run `sops updatekeys` on those files.
