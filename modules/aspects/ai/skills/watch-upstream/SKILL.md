---
name: watch-upstream
description: Automate a cleanup that is waiting for an upstream change to reach a flake input. Use for watching upstream PRs, removing vendored workarounds after landing, or unblocking a stacked change.
---

# Watch upstream

Record the workaround paths, the upstream condition, and the requested
completion actions. Preserve the user's scope: a notification-only request
does not authorize an automated cleanup or push.

## Define the gate

Create or update the gate in `data/upstream-gates.json`. It is the canonical
source for landing predicates, the input to update, owned paths, timer name,
and tracking issue. Use the existing schema and validate it with:

```bash
nix run .#upstream-gates -- validate
```

The checker distinguishes:

- `waiting-upstream`: the source change is unavailable.
- `waiting-unstable`: the source is ready, but the target branch is not.
- `waiting-pin`: the branch is ready, but this lockfile is behind.
- `adopting`: the exact pin is ready for cleanup, which has not yet completed.

Keep branch and pin predicates equivalent apart from their reference.
`nh search` helps discover changes; it does not prove that the exact lockfile
contains one. Record real upstream references, or use a source predicate when
no PR exists.

The `workaround` array is also the allowed edit list. Include every file the
cleanup changes, including consumers of a removed aspect. The runner also
allows `flake.lock`. Add the tracking issue URL when one exists.

## Implement cleanup

Use the tracked [runner](scripts/run.sh) and [gate actions](scripts/actions.sh).
Add the gate's three actions:

- `completed` reads the checkout and returns 0 for completed cleanup, 1 for
  remaining work, or another status for a failed inspection.
- `apply` performs the narrow cleanup. Check anchors before editing shared
  files; prefer removing a dedicated workaround and its includes.
- `verify` evaluates affected hosts and builds or exercises the behavior the
  workaround provided. Discover hosts from the flake instead of keeping a list.

The runner fetches `origin/main` and uses a unique detached worktree. It calls
the checker from that checkout, updates only the declared input for
`waiting-pin`, and rechecks the new lock before editing. Errors fail the run;
ordinary waiting exits 0. A per-gate lock prevents overlapping executions.

After cleanup it checks owned paths, validates, commits, and pushes without
force. It confirms completion on freshly fetched origin before closing the
tracking issue and disabling the timer. Failed validation, pushes, or issue
closure leave the timer armed for retry. The user's working files are never
pulled, reset, or used to decide completion.

## Verify and install

Run the isolated tests, which use a local bare Git repository and substitute
network, Nix-build, issue, and systemd operations:

```bash
node --test modules/aspects/ai/skills/watch-upstream/scripts/run.test.mjs
```

Tests cover the current cleanups, waiting states, failed checks, retries,
publication, and retirement. Add a case when a new cleanup needs another
observable assertion. CI also runs `checks.agent-skills` and
`checks.upstream-gates`.

Install the registered launchers:

```bash
bash modules/aspects/ai/skills/watch-upstream/scripts/install.sh "$PWD"
~/.local/bin/watch-qbittorrent.sh --check-only
```

The installer copies a versioned runner/action bundle under `~/.local/lib/`,
backs up replaced scripts there, and atomically replaces the launchers in
`~/.local/bin/`. It does not enable or start timers. Gate definitions must be
on `origin/main` before the installed runner can use them. `--check-only`
reports readiness or completion without updating inputs, applying changes,
pushing, closing issues, or changing timers.

For a new authorized automation, create a systemd user oneshot service whose
`ExecStart` is the installed launcher. Use a two-hour timer with
`Persistent=true` and `WantedBy=timers.target`, then enable and start it.
Confirm the next fire with `systemctl --user list-timers` and report the gate,
automatic actions, and logs at `journalctl --user -u <service>`.

## Retire

The runner disables the timer only after completion is confirmed on origin
and the tracking issue is closed. Once that is confirmed, remove its user
service and timer files, run `systemctl --user daemon-reload`, and verify that
they are gone. Remove the obsolete launcher and registry entry together with
its gate-specific actions. Historical reference scripts are unnecessary;
the maintained runner and tests remain in the repository.
