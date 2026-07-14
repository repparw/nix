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
| `secrets/nix.yaml` | `accessTokens` | Authenticate Nix fetches against private sources | Nix daemon configuration | `alpha` |
| `secrets/backup.yaml` | `resticPassword` | Unlock the encrypted Restic repository | Restic backup | `alpha` |
| `secrets/rclone.yaml` | `rcloneDriveId` | Identify the Google Drive OAuth client | rclone Home Manager services | `alpha` |
| `secrets/rclone.yaml` | `rcloneDriveToken` | Authorize Google Drive access | rclone Home Manager services | `alpha` |
| `secrets/rclone.yaml` | `rcloneDriveSecret` | Authenticate the Google Drive OAuth client | rclone Home Manager services | `alpha` |
| `secrets/rclone.yaml` | `rcloneCrypt` | Unlock the encrypted rclone remote | rclone Home Manager services | `alpha` |
| `secrets/rclone.yaml` | `rcloneClarodrive` | Authenticate the Claro Drive remote | rclone Home Manager services | `alpha` |
| `secrets/rclone.yaml` | `rcloneDropbox` | Authorize Dropbox access | rclone Home Manager services | `alpha` |
| `secrets/rclone.yaml` | `rcloneNextcloud` | Authenticate the Nextcloud remote | rclone Home Manager services | `alpha` |
| `secrets/proxy.yaml` | `cloudflare` | Authorize Cloudflare DNS-01 certificate updates | Traefik | `alpha` |
| `secrets/proxy.yaml` | `qbittorrentAuth` | Configure qBittorrent proxy authentication | Traefik | `alpha` |
| `secrets/ddclient.yaml` | `ddclientPassword` | Authorize dynamic DNS updates | ddclient | `alpha` |
| `secrets/authelia.yaml` | `authelia/jwtSecret` | Sign Authelia identity-verification tokens | Authelia | `alpha` |
| `secrets/authelia.yaml` | `authelia/oidcHmacSecret` | Protect Authelia OIDC authorization data | Authelia | `alpha` |
| `secrets/authelia.yaml` | `authelia/oidcJwksKey` | Sign Authelia OIDC tokens | Authelia | `alpha` |
| `secrets/authelia.yaml` | `authelia/sessionSecret` | Encrypt and authenticate Authelia sessions | Authelia | `alpha` |
| `secrets/authelia.yaml` | `authelia/smtpPassword` | Authenticate Authelia to its SMTP relay | Authelia | `alpha` |
| `secrets/authelia.yaml` | `authelia/storageEncryptionKey` | Encrypt sensitive Authelia storage fields | Authelia | `alpha` |
| `secrets/archisteamfarm.yaml` | `steamPassword` | Authenticate the managed Steam account | ArchiSteamFarm | `alpha` |
| `secrets/jellyfin.yaml` | `jellyfinBackupKey` | Authorize Jellyfin backup creation | Jellyfin backup tooling | `alpha` |
| `secrets/automations.yaml` | `discordWebhook` | Deliver automation notifications to Discord | Automation services | `alpha` |
| `secrets/streaming.yaml` | `sunshineApiUsername` | Authenticate Sunshine API health checks | Sunshine watchdog | `alpha` |
| `secrets/streaming.yaml` | `sunshineApiPassword` | Authenticate Sunshine API health checks | Sunshine watchdog | `alpha` |
The creation rule grants `alpha` only its SSH host-key recipient plus the
recovery recipient. Add a host recipient to only the files that host consumes,
then run `sops updatekeys` on those files.
