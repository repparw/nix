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

| SOPS file                          | Secret                          | Purpose                                                                                                                                                                                            | Consumer                                                       | Hosts                    |
| ---------------------------------- | ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- | ------------------------ |
| `secrets/nix.sops.yaml`            | `accessTokens`                  | Authenticate Nix fetches against private sources                                                                                                                                                   | Nix daemon configuration                                       | `alpha`                  |
| `secrets/backup.sops.yaml`         | `resticPassword`                | Unlock the encrypted Restic repository                                                                                                                                                             | Restic backup                                                  | `alpha`, `pi`, `epsilon` |
| `secrets/rclone.sops.yaml`         | `rcloneDriveId`                 | Identify the Google Drive OAuth client                                                                                                                                                             | rclone services and host backup                                | `alpha`, `pi`, `epsilon` |
| `secrets/rclone.sops.yaml`         | `rcloneDriveToken`              | Authorize Google Drive access                                                                                                                                                                      | rclone services and host backup                                | `alpha`, `pi`, `epsilon` |
| `secrets/rclone.sops.yaml`         | `rcloneDriveSecret`             | Authenticate the Google Drive OAuth client                                                                                                                                                         | rclone services and host backup                                | `alpha`, `pi`, `epsilon` |
| `secrets/rclone.sops.yaml`         | `rcloneCrypt`                   | Unlock the encrypted rclone remote                                                                                                                                                                 | rclone services and host backup                                | `alpha`, `pi`, `epsilon` |
| `secrets/rclone.sops.yaml`         | `rcloneObsidianCrypt`           | Unlock the Remotely Save-compatible Obsidian crypt remote                                                                                                                                          | Obsidian bisync service                                        | `alpha`                  |
| `secrets/rclone.sops.yaml`         | `rcloneClarodrive`              | Authenticate the Claro Drive remote                                                                                                                                                                | rclone Home Manager services                                   | `alpha`, `pi`            |
| `secrets/rclone.sops.yaml`         | `rcloneClarodriveUser`          | Identify the Claro Drive account (injected into the remote `user` at activation, never baked into the store)                                                                                       | rclone Home Manager services                                   | `alpha`, `pi`            |
| `secrets/rclone.sops.yaml`         | `rcloneClarodriveUrl`           | Claro Drive WebDAV endpoint carrying the account id (injected at activation)                                                                                                                       | rclone Home Manager services                                   | `alpha`, `pi`            |
| `secrets/rclone.sops.yaml`         | `rcloneDropbox`                 | Authorize Dropbox access                                                                                                                                                                           | rclone Home Manager services                                   | `alpha`, `pi`            |
| `secrets/rclone.sops.yaml`         | `rcloneNextcloud`               | Authenticate the Nextcloud remote                                                                                                                                                                  | rclone Home Manager services                                   | `alpha`, `pi`            |
| `secrets/proxy.sops.yaml`          | `cloudflare`                    | Authorize Cloudflare DNS-01 certificate updates                                                                                                                                                    | Traefik                                                        | `alpha`, `pi`            |
| `secrets/proxy.sops.yaml`          | `qbittorrentAuth`               | Configure qBittorrent proxy authentication                                                                                                                                                         | Traefik                                                        | `alpha`, `pi`            |
| `secrets/ddclient.sops.yaml`       | `ddclientPassword`              | Authorize dynamic DNS updates                                                                                                                                                                      | ddclient                                                       | `alpha`, `pi`            |
| `secrets/authelia.sops.yaml`       | `authelia/jwtSecret`            | Sign Authelia identity-verification tokens                                                                                                                                                         | Authelia                                                       | `epsilon`                |
| `secrets/authelia.sops.yaml`       | `authelia/oidcHmacSecret`       | Protect Authelia OIDC authorization data                                                                                                                                                           | Authelia                                                       | `epsilon`                |
| `secrets/authelia.sops.yaml`       | `authelia/oidcJwksKey`          | Sign Authelia OIDC tokens                                                                                                                                                                          | Authelia                                                       | `epsilon`                |
| `secrets/authelia.sops.yaml`       | `authelia/sessionSecret`        | Encrypt and authenticate Authelia sessions                                                                                                                                                         | Authelia                                                       | `epsilon`                |
| `secrets/authelia.sops.yaml`       | `authelia/smtpPassword`         | Authenticate Authelia to its SMTP relay                                                                                                                                                            | Authelia                                                       | `epsilon`                |
| `secrets/authelia.sops.yaml`       | `authelia/storageEncryptionKey` | Encrypt sensitive Authelia storage fields                                                                                                                                                          | Authelia                                                       | `epsilon`                |
| `secrets/authelia-users.sops.yaml` | `usersDatabase`                 | Seed Authelia's initial users database when the writable runtime file is absent                                                                                                                    | Authelia                                                       | `epsilon`                |
| `secrets/users-pi.sops.yaml`       | `repparwPasswordHash`           | Bootstrap the Pi account password when the user is created; existing passwords remain mutable                                                                                                      | NixOS user creation                                            | `pi`                     |
| `secrets/users-epsilon.sops.yaml`  | `repparwPasswordHash`           | Bootstrap the epsilon account password when the user is created; existing passwords remain mutable                                                                                                 | NixOS user creation                                            | `epsilon`                |
| `secrets/archisteamfarm.sops.yaml` | `steamPassword`                 | Authenticate the managed Steam account                                                                                                                                                             | ArchiSteamFarm                                                 | `epsilon`                |
| `secrets/archisteamfarm.sops.yaml` | `steamUsername`                 | Identify the managed Steam account (substituted into the bot config at runtime via `replace-secret`; ASF only accepts a literal `SteamLogin`)                                                      | ArchiSteamFarm                                                 | `epsilon`                |
| `secrets/home.sops.yaml`           | `homeWanIp`                     | Home WAN IP: populates the `home-wan` nft set and the `wg-home` endpoint at boot via the `home-wan` service (firewall/WG strings render at evaluation time, so SOPS feeds them at runtime instead) | home uplink provisioning                                       | `epsilon`                |
| `secrets/bluetooth.sops.yaml`      | `btDevice`                      | Bluetooth MAC targeted by `bttoggle`, read as a fallback when `TOGGLE_BT_DEVICE` is unset                                                                                                          | bttoggle helper                                                | `alpha`                  |
| `secrets/jellyfin.sops.yaml`       | `jellyfinBackupKey`             | Authorize Jellyfin backup creation                                                                                                                                                                 | Jellyfin backup tooling                                        | `alpha`                  |
| `secrets/automations.sops.yaml`    | `discordWebhook`                | Deliver automation notifications to Discord                                                                                                                                                        | Automation services                                            | `pi`                     |
| `secrets/matriz.sops.yaml`         | `matrizApiUsername`             | Identify the EcoValores Matriz API user without publishing its CUIT                                                                                                                                | Matriz account snapshot service                                | `alpha`                  |
| `secrets/matriz.sops.yaml`         | `matrizApiPassword`             | Authenticate the local EcoValores Matriz adapter                                                                                                                                                   | Matriz account snapshot service                                | `alpha`                  |
| `secrets/matriz.sops.yaml`         | `matrizApiAccount`              | Select the EcoValores Matriz account without publishing its identifier                                                                                                                             | Matriz account snapshot service                                | `alpha`                  |
| `secrets/hermes.sops.yaml`         | `hermes-env`                    | Discord token for the Hermes gateway plus fleet-wide Discord notify (fleet-update, backup, fleet-health source it on every host)                                                                   | `services.hermes-agent` environmentFiles, fleet notify scripts | fleet-wide               |
| `secrets/hermes.sops.yaml`         | `hermes-llm-env`                | Agent LLM/tool API keys (OpenCode, OpenRouter, Exa, GH); declared in the Hermes aspect so only epsilon decrypts it                                                                                 | `services.hermes-agent` environmentFiles                       | `epsilon`                |
| `secrets/hermes-arr.sops.yaml` | `arr-api-keys` | Authenticate Sonarr/Radarr queue-triage requests | Hermes tool subprocesses | `epsilon` |

The account-password bootstrap files and Authelia users seed are scoped to the
personal recovery recipient and the consuming host. The remaining files use
the legacy shared creation rule in `.sops.yaml`. When changing a creation rule,
run `sops updatekeys` on the affected files and verify their embedded recipient
metadata matches the rule.

NixOS decrypts with the machine SSH host key at
`/etc/ssh/ssh_host_ed25519_key`; the personal Age recipient in `.sops.yaml` is
recovery access and is not used during activation. Docs, plans, and commits
should refer to SOPS secret names or source modules, never secret values.

## Account password and Authelia user provisioning

The pi and epsilon password hashes are stored in separate SOPS files and
materialized early with `neededForUsers`; each host points
`users.users.repparw.hashedPasswordFile` at its own hash. The default
`users.mutableUsers = true` policy is unchanged, so NixOS uses these password
options when creating the account but does not overwrite an existing account's
password on later activations. Normal `passwd` changes therefore remain
authoritative. If an imperative password change should also become the
bootstrap password for a rebuilt host, update its SOPS value separately.

The bootstrap files use narrower recipient rules than the legacy shared rule:
the personal recovery recipient plus only the consuming host recipient. Existing
ciphertext must be rekeyed with `sops updatekeys` after this change so its
embedded recipients match those rules.

`authelia-users.sops.yaml` is a bootstrap copy of the current user database.
Authelia continues to use the writable
`/home/containers/config/authelia/config/users_database.yml`; systemd seeds it
from the SOPS credential only when that file is absent. Existing runtime
password resets and user edits therefore remain authoritative. Back up the
mutable file before intentionally removing it to request a fresh seed.

## Eval-time values via runtime provisioning (not SOPS-at-eval)

SOPS only materializes at activation, but firewall strings and the
WireGuard endpoint render at evaluation time. For those, the committed
config carries structure only (an empty `home-wan` nft set, an endpoint-less
peer) and a `home-wan` oneshot fills both from `homeWanIp` at boot,
re-running when the secret changes. An empty set matches nothing, so a
missing secret fails closed; a malformed one fails the unit loudly. The
Bluetooth MAC rides the same pattern one level simpler: `bttoggle` reads
the user-owned `btDevice` secret file when `TOGGLE_BT_DEVICE` is unset.

## Source

- `modules/aspects/secrets.nix`
- `secrets/`

## Related

- [Repository layout](repository-layout.md)
