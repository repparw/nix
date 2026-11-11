---
type: Architecture Concept
when: Read when adding, consuming, rotating, or documenting SOPS secrets.
title: Secret handling and recovery
description: Secret authority, rotation and recovery rules that are not visible from declarations alone.
resource: secrets
tags: [security, secrets, sops-nix]
---

# Secret handling and recovery

Secret identifiers and consumers are declared as `sops.secrets` in their
owning Nix host and service modules. The encrypted `secrets/*.sops.yaml`
files carry ciphertext and recipient metadata; the shared
[sops-nix aspect](../../modules/aspects/secrets.nix) configures decryption,
not the per-secret inventory. Search the Nix sources rather than copying an
inventory into Markdown, and never commit decrypted values.

There are two distinct authorities:

- The `.sops.yaml` policy describes **intended recipients** for new or
  rekeyed ciphertext; each encrypted file's embedded recipients determine
  who can **currently decrypt it**. After changing recipient policy, rekey
  the existing ciphertext and test the consuming host.
- Runtime writable credentials can override bootstrap values. A successful
  rebuild does not prove a service adopted a rotated token or that an
  existing account password has been overwritten.

The procedures below document cases where updating a secret alone does
not complete the operation.

## Hermes T3 MCP token rotation

The `hermes-t3-mcp` bearer session on alpha is issued for 365 days and
loaded into Hermes on epsilon from `hermes-llm-env`. Its read and operate
scopes allow it to direct T3 threads, so revoke it immediately if compromised.

1. Issue a new `mcp-client` session on alpha with the same label, scopes
   (`orchestration:read` and `orchestration:operate`), and a 365-day TTL.
2. Replace only `T3_MCP_TOKEN` in the SOPS `hermes-llm-env` value and
   deploy epsilon. The secret has a `container@hermes.service` restart trigger.
3. Verify an actual Hermes-initiated T3 MCP tool call on epsilon using the
   newly deployed configuration. Issuing the session or checking it from alpha
   does **not** prove that Hermes loaded the new credential.
4. On alpha, identify the **new** session ID from `t3 auth session list --json`
   (check its `issuedAt` and `expiresAt`). After step 3 succeeds, acknowledge
   this specific ID in the watcher's state directory:

   ```sh
   sudo install -d -m 0755 /var/lib/t3-token-watch
   printf '%s\n' '<new-session-id>' | sudo tee /var/lib/t3-token-watch/verified-session-id >/dev/null
   ```

   The session ID is metadata, **not** the bearer token. Never store the bearer
   token in this file.

5. Revoke the old session on alpha, then confirm `t3 auth session list --json`
   reports exactly one active session with label `hermes-t3-mcp`. Run
   `sudo systemctl start t3-token-watch` and check that its
   `/var/lib/t3-token-watch/last-band` state is `ok`.

Alpha's daily `t3-token-watch` cannot inspect the credential loaded by
Hermes on epsilon. It reports overlapping sessions and replacement session
IDs lacking the post-deployment acknowledgment, with weekly reminders until
resolved. The watcher only tracks expiry when one labeled session remains and
its ID matches the acknowledged one. A healthy expiry report does **not**
replace the MCP probe in step 3.

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
