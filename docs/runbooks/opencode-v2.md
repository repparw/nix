---
type: Runbook
title: Test OpenCode v2 alongside v1
description: Isolated OpenCode v2 package, provider, data migration, and rollback boundaries.
when: Read before trying OpenCode v2 or replacing the v1 provider.
resource: modules/aspects/ai/opencode-v2.nix
tags: [opencode, migration, ai, t3code, backups]
---

# Test OpenCode v2 alongside v1

Alpha includes the `opencode-v2` aspect. It installs `opencode2` and adds an
`OpenCode 2` T3 provider. V1 keeps its binary, web service, and provider ID.
T3 starts and authenticates the v2 server through the separate launcher.

V2 uses separate XDG roots named `opencode-v2`. Its database is
`~/.local/share/opencode-v2/opencode/opencode.db`, and its generated configuration
is `~/.config/opencode-v2/opencode/opencode.json`. The launcher also isolates
cache and state. Skills and global instructions link to the existing files.
The v2 Nous plugin resolves migrated credentials through the native integration
API, discovers the account's catalog, and exposes only `:free` routes with the
required user tag. V1 also filters strictly to `:free` routes.

## Seed and verify history

Before the first v2 launch, make a private SQLite online backup of the current
v1 database. Use SQLite's backup API rather than copying a live WAL database.
Keep an untouched backup and a separate rehearsal copy. Include `auth.json`
and `account.json` in the private backup; neither belongs in Git or the Nix
store. Seed the separate v2 data directory from the current database backup
and copies of those credential files.

If v2 has already started, stop its writers and back up its namespace before
seeding. Use a fresh namespace if it contains v2 history. Replace an empty
auto-created database only after confirming that it has no sessions.

An older `opencode-stable.db` may also contain history. Back it up and rehearse
it separately. Do not overwrite the current database with it or combine the
two based only on their filenames.

Run v2 against the rehearsal's isolated XDG directories. Wait for
`GET /api/experimental/migration/v1` to report `completed`; HTTP readiness
alone does not establish migration completion. Require SQLite integrity, every
original session ID, and original text content in the corresponding migrated
sessions. Message IDs can change when migration pairs records, so compare
content by session as well as inspecting counts.

Verify credentials, custom agents, MCP servers, plugin status, model inventory,
and a real model/tool round trip. T3 must identify the executable as v2 and
load its catalog. Do not interpret a successful package build as runtime proof.

## Switch and rollback

V1 and v2 can remain available together. Preserve each existing thread's
provider selection while testing new v2 work. A v1 turn still running after a
snapshot can append history that is absent from the v2 copy. Quiesce those
writers and take a fresh backup before a final replacement.

Rollback means selecting the retained v1 provider and data. Never point v1 at
a migrated v2 database, and never overwrite v2 data with a v1 backup after new
v2 work has begun.

The temporary source package is taken from Nixpkgs PR #569770 at commit
`3a37a0e661f12c9946354a39c754dd8eb3b3e501`, with source and dependency hashes
pinned. Retire the local package after equivalent upstream packaging reaches
the repository's root Nixpkgs pin and passes these checks.
