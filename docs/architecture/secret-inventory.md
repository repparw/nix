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

## Hermes T3 MCP connection

Hermes on epsilon uses one OAuth 2.0 MCP connection, `t3code`, to Epsilon's
relay with the Auto scope set (`orchestration:read` and
`orchestration:operate`). Alpha and Pi are reached through Epsilon's linked
environments rather than separate credentials. Effective access is the lower of
the client scopes and the link's access level, so remote work stays at Auto.
Tokens live in Hermes' home under `.hermes/mcp-tokens/`; they are neither
committed nor stored in SOPS.

Re-enrollment needs a human approval step. `hermes mcp login t3code` binds a
loopback callback listener on port 27890 and prints an authorize URL. Open it
in a browser signed in to the relay, or paste a short-lived code from
`t3 auth pairing create --scope orchestration:read --scope
orchestration:operate`, choose Auto, and approve. In the headless container,
forward that loopback port to the browser's machine or paste the redirect URL
into the prompt. Do not script the approval.

If the connection breaks, re-enroll before touching anything else: the legacy
per-host bearer tokens are gone, so there is no fallback credential. Prove
recovery with a real Hermes-initiated call, such as `hermes chat -q` reading
`t3_environment_links`.

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
