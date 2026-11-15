---
type: Architecture Concept
when: Read when adding, consuming, rotating, or documenting SOPS secrets.
title: Secret handling and recovery
description: Secret authority, rotation and recovery rules that are not visible from declarations alone.
resource: secrets
tags: [security, secrets, sops-nix]
---

# Secret handling and recovery

Each host and service module declares its secrets as `sops.secrets`, which names
each secret and its consumers. The encrypted `secrets/*.sops.yaml` files carry
ciphertext and recipient metadata. The shared
[sops-nix aspect](../../modules/aspects/secrets.nix) configures decryption, and
it does not hold a per-secret inventory. Search the Nix sources instead of
copying an inventory into Markdown, and never commit decrypted values.

Two separate authorities apply:

- The `.sops.yaml` policy describes the intended recipients for new or rekeyed
  ciphertext. The recipients embedded in each encrypted file decide who can
  decrypt it now. After you change the recipient policy, rekey the existing
  ciphertext and test the consuming host.
- Runtime writable credentials can override bootstrap values. A successful
  rebuild does not prove that a service adopted a rotated token, or that an
  existing account password was overwritten.

The procedures below cover cases where updating a secret alone does not complete
the operation.

## Hermes T3 MCP token rotation

The `hermes-t3-mcp` bearer session on alpha is issued for 365 days. Hermes on
epsilon loads it from `hermes-llm-env`. Its read and operate scopes let it
direct T3 threads, so revoke it immediately if it is compromised.

1. Issue a new `mcp-client` session on alpha with the same label, the same
   scopes (`orchestration:read` and `orchestration:operate`), and a 365-day TTL.
2. Replace only `T3_MCP_TOKEN` in the SOPS `hermes-llm-env` value, and deploy
   epsilon. The secret has a `container@hermes.service` restart trigger.
3. Verify an actual Hermes-initiated T3 MCP tool call on epsilon, using the newly
   deployed configuration. Issuing the session, or checking it from alpha, does
   not prove that Hermes loaded the new credential.
4. On alpha, find the new session ID with `t3 auth session list --json`, and
   check its `issuedAt` and `expiresAt`. After step 3 succeeds, acknowledge that
   specific ID in the watcher's state directory:

   ```sh
   printf 'Verified new session ID: ' >&2
   IFS= read -r new_session_id
   test -n "$new_session_id" || exit 1
   sudo install -d -m 0755 /var/lib/t3-token-watch
   printf '%s\n' "$new_session_id" | sudo tee /var/lib/t3-token-watch/verified-session-id >/dev/null
   ```

   The session ID is metadata, not the bearer token. Never store the bearer
   token in this file.

5. Revoke the old session on alpha. Then confirm that
   `t3 auth session list --json` reports exactly one active session with the
   label `hermes-t3-mcp`. Run `sudo systemctl start t3-token-watch`, and check
   that `/var/lib/t3-token-watch/last-band` says `ok`.

Alpha's daily `t3-token-watch` cannot inspect the credential that Hermes loaded
on epsilon. It reports overlapping sessions and replacement session IDs that
lack the post-deployment acknowledgment, with weekly reminders until you resolve
them. The watcher tracks expiry only when one labeled session remains and its ID
matches the acknowledged one. A healthy expiry report does not replace the MCP
probe in step 3.

## Account password and Authelia user provisioning

The pi and epsilon password hashes live in separate SOPS files, and each host
materializes its file early with `neededForUsers`. Each host points
`users.users.repparw.hashedPasswordFile` at its own hash. The default
`users.mutableUsers = true` policy is unchanged. NixOS therefore uses these
password options when it creates the account, but it does not overwrite an
existing account's password on later activations, so normal `passwd` changes
stay authoritative. If an imperative password change should also become the
bootstrap password for a rebuilt host, update its SOPS value separately.

The bootstrap files use narrower recipient rules than the legacy shared rule.
Each file's recipients are the personal recovery recipient and only the
consuming host's recipient. Rekey existing ciphertext with `sops updatekeys` so
its embedded recipients match those rules.

`authelia-users.sops.yaml` is a bootstrap copy of the current user database.
Authelia keeps using the writable
`/home/containers/config/authelia/config/users_database.yml`. systemd seeds that
file from the SOPS credential only when it is absent. Runtime password resets
and user edits therefore stay authoritative. Before you intentionally remove the
mutable file to request a fresh seed, back it up.

## Evaluation-time values and runtime provisioning

SOPS materializes secrets only at activation, but firewall strings and the
WireGuard endpoint render at evaluation time. For those values, the committed
configuration holds only structure: an empty `home-wan` nft set and an
endpoint-less peer. A `home-wan` oneshot fills both from `homeWanIp` at boot, and
it runs again when the secret changes. An empty set matches nothing, so a
missing secret fails closed. A malformed secret makes the unit fail with an
error. The Bluetooth MAC follows the same pattern in a simpler form. `bttoggle`
reads the user-owned `btDevice` secret file when `TOGGLE_BT_DEVICE` is unset.

## Source

- `modules/aspects/secrets.nix`
- `secrets/`
