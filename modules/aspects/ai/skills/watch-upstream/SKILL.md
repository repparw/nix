---
description: Use for "watch until upstream lands", "when nixpkgs/home-manager PR X merges", "unblock when upstream", "remove the vendored workaround after", or any blocked-on-upstream cleanup: set an autonomous probe that completes the unblock (bump pin, drop workaround, merge the stacked PR) without human intervention.
---

# Watch upstream

A change is blocked on an upstream commit (nixpkgs, home-manager, a project repo) landing on the ref you pin. Your job has two halves and both are yours:

1. **Arm** an autonomous probe that detects the landing.
2. **Complete** the unblock — finish the cleanup work, don't just report it.

The human said "merge when it lands", not "tell me when it lands". Design for a run where nobody is at the keyboard.

## Step 1: Identify the blocker

Find three things and state them back to the human before arming anything:

- **Workaround** — the vendored code standing in for upstream: a `builtins.fetchurl` of a module file, a `nixpkgs.overlays` patch, a flake input, a patched package. Exact file paths and line numbers.
- **Upstream event** — the precise observable condition meaning "landed": a file exists at a raw URL on the pinned branch (`https://raw.githubusercontent.com/<org>/<repo>/<branch>/<path>` → 200), or a PR's `merged_at` plus the pin's branch containing the merge commit.
- **Completion actions** — everything that becomes possible once landed: bump the lockfile pin, delete the fetchurl block, mark the draft PR ready and merge it, close the tracking issue, remove now-dead flake inputs.
- **Mechanical seam** — restructure the workaround so completion is mechanical: give vendored code its own file/provide and reference it through single-line includes from *every* consumer (a host including sub-aspects individually must be listed explicitly). Removal then is `git rm` + deleting include lines, never regex surgery on code that will have evolved by the time the probe fires.

**Done when**: the human could read your three-part summary and correct any part before the probe ever fires.

## Step 2: Gate on verification, not detection

Detection alone is not permission to act. Between "URL returns 200" and "merge the cleanup PR" there must be a **gate**: run the thing that breaks if you guessed wrong, and abort leaving state untouched if it fails.

For a Nix flake: `nix flake update <input>`, then eval the option that previously came from the vendored module for every affected host. Only eval success authorizes the commit.

For a package patch removal: build the package from the new pin first.

If the gate fails after detection succeeded, exit non-zero with the failure visible — that combination means the upstream change differs from what the workaround assumed, and a human must look.

## Step 3: Arm the probe

This machine has no cron. Use a systemd user timer pair in `~/.config/systemd/user/`:

- `<name>.service` — `Type=oneshot`, `ExecStart=<script>`.
- `<name>.timer` — `OnCalendar=*-*-* 00/2:17:00` (every 2h at :17), **`Persistent=true`** so reboots and missed runs replay, `WantedBy=timers.target`.

Then `systemctl --user daemon-reload && systemctl --user enable --now <name>.timer`.

The script itself goes in `~/.local/bin/<name>.sh`, never in the repo. One-off watchers are machine-local tooling; committing one pollutes git history for every future reader. Hardcode the repo path in the script (`REPO="$HOME/Projects/nix"`) instead of deriving it from `$0`.

Probe cadence: upstream channels batch promotions daily; 2h is plenty. Faster polling buys nothing.

## Step 4: The script contract

Every watcher script must satisfy all five properties:

1. **Quiet while waiting** — probe fails to match → print one line, `exit 0`. A not-ready state is success for a watcher; non-zero there just pollutes journals.
2. **Idempotent** — detect "already done" first (e.g. head branch no longer exists on origin = PR already merged) and disable the timer instead of redoing work.
3. **Narrow writes** — stage only files the unblock owns (usually just the lockfile). Never sweep unrelated dirty working-tree files into the completion commit.
4. **Self-disarming** — on full success, `systemctl --user disable --now <name>.timer`. A completed watcher left running is sediment.
5. **Observable** — humans find results via `journalctl --user -u <name>.service`; every decision prints a line.

Reference implementations (machine-local, deliberately outside git): `~/.local/bin/watch-moonshine.sh` and `~/.local/bin/watch-t3code-title-fix.sh` — the latter probes nixos-unstable's packaged t3code version → bumps the pin → removes the `t3code-title-patch` aspect and its include lines → gates on per-host eval plus a real build of the unpatched package → pushes → disarms itself.

## Step 5: Verify armed, report

Run the script once by hand. Confirm: exits 0 on the not-ready path, journal shows the line, `list-timers` shows the next fire.

Gotcha when verifying the repo side: Nix flakes only see git-tracked files, so a newly added workaround file must be staged (`git add`) before any eval against the working tree can resolve it.

Report to the human: what is being watched, the exact condition, what will happen automatically, where the log lives, and the manual command that does the same thing (`journalctl --user -u <name> -f`) for watching live.

**Done when**: the probe survives a restart (Persistent=true confirmed), and the completion path is verified either by a dry-run of its early steps or by explicit reasoning over each command in it.
