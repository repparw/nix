---
type: Runbook
title: Obsidian rclone bisync
description: Bootstrap and operate the Neovim-first Obsidian vault sync.
when: Read when bootstrapping, operating, or recovering Obsidian rclone bisync.
resource: modules/aspects/obsidian.nix
tags: [obsidian, rclone, bisync, dropbox]
---

# Operate Obsidian bisync

Neovim edits `~/Documents/obsidian`; a user service syncs it with the encrypted
Remotely Save Dropbox vault. Paths, filters, and timer behavior are declared in
[obsidian.nix](../../modules/aspects/obsidian.nix).

## Bootstrap or rebuild a missing baseline

Pause edits on PC and phone. Complete the phone's final Remotely Save sync,
close Obsidian on the PC, and stop the scheduled sync:

```sh
systemctl --user stop obsidian-bisync.timer
systemctl --user stop obsidian-bisync.service
```

1. Preserve both plaintext and exact ciphertext snapshots:

   ```sh
   stamp="$(date +%Y%m%d-%H%M%S)"
   cp -a "$HOME/Documents/obsidian" "$HOME/Documents/obsidian.pre-rclone-$stamp"
   mkdir -p "$HOME/.local/state/obsidian-remote-backups/$stamp"
   rclone copy 'dropbox:Apps/remotely-save/obsidian' \
     "$HOME/.local/state/obsidian-remote-backups/$stamp" --create-empty-src-dirs
   ```

2. Validate decryption and the remote path. Stop on errors, an empty result,
   or unexpected contents:

   ```sh
   rclone lsf 'obsidian-rs-crypt:' --max-depth 2
   rclone size 'obsidian-rs-crypt:'
   ```

3. Stage the decrypted remote and compare it with the local vault:

   ```sh
   stage="$(mktemp -d)"
   rclone copy 'obsidian-rs-crypt:' "$stage" --create-empty-src-dirs
   diff -qr --exclude=.git --exclude=.obsidian --exclude=.trash \
     "$HOME/Documents/obsidian" "$stage"
   ```

   Preserve both versions of differing files and merge remote-only changes
   before choosing the local vault as canonical. Timestamps alone are not
   sufficient. Retain staging and snapshots until verification completes.

4. Create the access marker on both sides:

   ```sh
   touch "$HOME/Documents/obsidian/RCLONE_TEST"
   rclone copyto "$HOME/Documents/obsidian/RCLONE_TEST" 'obsidian-rs-crypt:RCLONE_TEST'
   ```

5. Preview resync, review every operation, then repeat without `--dry-run`:

   ```sh
   rclone bisync "$HOME/Documents/obsidian" 'obsidian-rs-crypt:' \
     --workdir "${XDG_STATE_HOME:-$HOME/.local/state}/rclone/obsidian-bisync" \
     --resync-mode path1 \
     --filters-file "$HOME/.config/rclone/obsidian-bisync.filter" \
     --check-access --max-delete 10 --dry-run -vv
   ```

6. Run the normal service, inspect the journal, and check representative
   local-only and remote-only files before enabling the timer:

   ```sh
   systemctl --user start obsidian-bisync.service
   journalctl --user -u obsidian-bisync.service -n 100
   systemctl --user start obsidian-bisync.timer
   ```

## Preserve listing state

`${XDG_STATE_HOME:-$HOME/.local/state}/rclone/obsidian-bisync` contains required
Path1/Path2 listings. Manual commands must use the same workdir, paths, and filters.
Do not treat listings as disposable cache or add resync flags to the timer.

To migrate an existing baseline, stop the service and timer, preserve the old
workdir, and copy only the matching valid listings into an inspected destination.
Do not copy a live lock or overwrite an existing baseline blindly. Missing
listings require the bootstrap procedure above; `--recover` cannot recreate
an absent baseline ([bisync manual](https://rclone.org/bisync/)).

For an unexpected result, stop both units and preserve the workdir before
choosing either snapshot for restoration. A dry run alone does not establish
that a working incremental baseline exists.
