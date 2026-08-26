---
type: Runbook
title: Obsidian rclone bisync
description: Bootstrap and operate the Neovim-first Obsidian vault sync.
when: Read when bootstrapping, operating, or recovering Obsidian rclone bisync.
resource: modules/aspects/obsidian.nix
tags: [obsidian, rclone, bisync, dropbox]
---

# Obsidian rclone bisync

The desktop vault is `/home/repparw/Documents/obsidian`. Neovim edits the
plaintext vault locally; a Home Manager user service synchronizes content with
the encrypted Remotely Save Dropbox vault. Obsidian remains installed for
occasional GUI use but is not the desktop sync client.

Discovered remote records:

```text
LOCAL_VAULT=/home/repparw/Documents/obsidian
DROPBOX_REMOTE=dropbox
VAULT_NAME=obsidian
CRYPT_REMOTE=obsidian-rs-crypt
RCLONE_CONFIG=/home/repparw/.config/rclone/rclone.conf
REMOTE_PATH=dropbox:Apps/remotely-save/obsidian
```

The existing Remotely Save settings decode to `encryptionMethod=rclone-base64`.
The managed crypt wrapper therefore sets `filename_encoding = base64` and uses
the separate `rcloneObsidianCrypt` SOPS secret. The existing `crypt` remote and
its password are unrelated and remain unchanged.

## Initial bootstrap

Do this once, while edits are paused on both the PC and phone. Do not run the
scheduled service before completing the bootstrap.

1. Complete one final Remotely Save sync on the phone, and close Obsidian on
   the PC. Stop the timer while bootstrapping:

   ```bash
   systemctl --user stop obsidian-bisync.timer
   systemctl --user stop obsidian-bisync.service
   ```

2. Make a plaintext snapshot and an exact ciphertext snapshot:

   ```bash
   stamp="$(date +%Y%m%d-%H%M%S)"
   cp -a "$HOME/Documents/obsidian" "$HOME/Documents/obsidian.pre-rclone-$stamp"
   mkdir -p "$HOME/.local/state/obsidian-remote-backups/$stamp"
   rclone copy \
     'dropbox:Apps/remotely-save/obsidian' \
     "$HOME/.local/state/obsidian-remote-backups/$stamp" \
     --create-empty-src-dirs
   ```

3. Validate decryption before any bisync write:

   ```bash
   rclone lsf 'obsidian-rs-crypt:' --max-depth 2
   rclone size 'obsidian-rs-crypt:'
   ```

   Stop if this is empty, reports decryption errors, or does not resemble the
   vault. In particular, do not continue with a wrong path or password.

4. Copy the decrypted remote to a temporary staging directory, compare it
   against the local vault while excluding `.git`, `.obsidian`, and `.trash`,
   and merge any required remote-only changes into the local vault:

   ```bash
   stage="$(mktemp -d)"
   rclone copy 'obsidian-rs-crypt:' "$stage" --create-empty-src-dirs
   diff -qr \
     --exclude=.git \
     --exclude=.obsidian \
     --exclude=.trash \
     "$HOME/Documents/obsidian" \
     "$stage"
   ```

   Keep the staging directory until the comparison is reviewed.

5. Mark the reconciled local vault as canonical and create the access marker:

   ```bash
   touch "$HOME/Documents/obsidian/RCLONE_TEST"
   rclone copyto \
     "$HOME/Documents/obsidian/RCLONE_TEST" \
     'obsidian-rs-crypt:RCLONE_TEST'
   ```

6. Preview the initial resync, review every operation, then repeat without
   `--dry-run`:

   ```bash
   rclone bisync \
     "$HOME/Documents/obsidian" \
     'obsidian-rs-crypt:' \
     --resync-mode path1 \
     --filters-file "$HOME/.config/rclone/obsidian-bisync.filter" \
     --check-access \
     --max-delete 10 \
     --dry-run \
     -vv
   ```

The normal service intentionally has no `--resync` or `--resync-mode` flag.
It uses `--recover`, `--resilient`, `--check-access`, a delete limit of 10,
and preserves losing conflict copies with `.pc` or `.dropbox` suffixes.

## Operation

```bash
systemctl --user start obsidian-bisync.service
systemctl --user status obsidian-bisync.service
systemctl --user status obsidian-bisync.timer
journalctl --user -u obsidian-bisync.service -n 100
```

The timer runs two minutes after user-manager startup and two minutes after a
completed run, so a long sync cannot overlap the next one. `.git`, `.obsidian`,
`.trash`, macOS metadata, and Windows thumbnail metadata are excluded from
cloud sync; conflict copies remain visible to Git.

## Rollback

```bash
systemctl --user stop obsidian-bisync.timer
systemctl --user stop obsidian-bisync.service
```

Inspect the journal and `~/.cache/rclone/bisync` state before restoring either
snapshot. Do not run a resync blindly.
