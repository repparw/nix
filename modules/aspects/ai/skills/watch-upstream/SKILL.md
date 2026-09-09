---
name: watch-upstream
description: 'Use for "watch until upstream lands", "when nixpkgs/home-manager PR X merges", "unblock when upstream", "remove the vendored workaround after", or any blocked-on-upstream cleanup: set an autonomous probe that completes the unblock (bump pin, drop workaround, merge the stacked PR) without human intervention.'
---

# Watch upstream

A change is blocked on an upstream landing. Both halves are yours:

1. **Arm** a probe that detects the landing.
2. **Complete** the cleanup. "Tell me when it lands" is not done.

## Before arming

State three things back to the human for correction:

- **Workaround**: exact file paths and lines of what stands in for upstream.
- **Upstream event**: the precise observable condition meaning "landed" (a raw URL returns 200 on the pinned branch, or a PR's `merged_at` plus the pin containing the merge commit).
- **Completion actions**: everything that becomes possible once landed, as mechanical edits.

Create or update the matching gate in `data/upstream-gates.json` before arming
the timer, then run `nix run .#upstream-gates -- validate`. The registry is the
canonical state; the timer, issue, and this skill are linked mechanisms. Use
`nix run .#upstream-gates -- check <gate-id>` to derive the state:

- `waiting-upstream`: the release, commit, or PR is not available.
- `waiting-unstable`: upstream has it, but the target branch does not.
- `waiting-pin`: the target branch has it, but the exact `flake.lock` revision does not.
- `adopting`: the exact lock contains it and the guarded cleanup can run.

Never collapse `waiting-unstable` and `waiting-pin`: the former cannot be
fixed by the next lock update, while the latter can. Record the input,
authoritative branch, exact channel and pin predicates, workaround paths, and
completion action. If no upstream PR exists, use a release or source
predicate; do not invent a PR number.

Each gate defines `input`, `repository`, `branch`, `source`, `channel`, `pin`,
`workaround`, `completion`, `watcher`, `issue`, and `upstream`. Predicates use
`file-contains`, `package-version`, `package-release-version`,
`package-tag-contains-commits`, or `commit-in-branch`/`commit-in-pin`; keep the
channel and pin predicates equivalent except for their reference.

Restructure first if needed: vendored code gets its own file/provide included by single lines from every consumer, so completion is `git rm` plus deleting include lines, never regex surgery.

## The probe

No cron on this machine. Systemd user pair in `~/.config/systemd/user/`: `<name>.service` (`Type=oneshot`, `ExecStart=<script>`) and `<name>.timer` (`OnCalendar=*-*-* 00/2:17:00`, **`Persistent=true`**, `WantedBy=timers.target`). Then enable and start it. Two hours is plenty; faster buys nothing.

The script goes in `~/.local/bin/<name>.sh`, never in the repo. Hardcode `REPO="$HOME/Projects/nix"`.

The probe's comments, notifications, and completion commit should include the
gate ID. It should call the checker before acting and distinguish its branch
and pin predicates. `nh search` is useful for discovery, but is not proof of a
specific branch or lockfile revision. For package waits, use the target
package source path and semantic version or behavior predicate; a moving
channel result is not proof that this flake's pin has landed it.

## Script contract

Every watcher must satisfy all five:

1. **Quiet while waiting**: not-ready prints one line, exits 0. Non-zero there pollutes journals.
2. **Idempotent**: detect "already done" and disable the timer instead of redoing work.
3. **Narrow writes**: stage only files the unblock owns. Detection and gating run in a pristine worktree from `origin/main` and must not read the working copy; only steps that mutate the local checkout (the convenience pull) may check for a dirty tree, and they stay guarded so dirt merely skips them.
4. **Gate before pushing**: after detection, run what breaks if you guessed wrong (flake update then eval every host; build the unpatched package). Gate failure means revert local state untouched, exit non-zero, notify. Detection alone is not permission to act.
5. **Self-disarming**: full success disables the timer.

Bash/awk only; python3 is not on systemd's default PATH. Gotchas: gawk treats `-v var="123"` as a string, so write `NR > (s + 0)` or line comparisons match lexicographically; flakes only see git-tracked files, so stage new workaround files before any eval against the tree.

## Verify armed, report

Run the script once by hand (expect the not-ready path), confirm `list-timers` shows the next fire. Report: what is watched, the condition, what happens automatically, where logs live (`journalctl --user -u <name>`), and that the probe survives restarts.

Reference implementations (machine-local): `watch-t3code-title-fix.sh`, `watch-tasks-org.sh`, `watch-qbittorrent.sh`, `watch-t3code-server.sh`, `watch-t3code-split.sh`.

## Dropping a watcher

When the upstream event is permanently satisfied (branch merged and gone, workaround removed on `origin/main`, tracking issue closed), retire the probe instead of leaving a disabled timer behind:

1. **Confirm done on origin, not the worktree**: branch gone (`ls-remote --heads origin <branch>` empty), workaround files absent from `origin/main`, issue closed. Local checkout state is irrelevant.
2. **Run the script by hand**: expect its idempotent disarm path (disable timer, prune worktree), exit 0. This doubles as proof the disarm branch works.
3. **Remove the dead units**: `rm ~/.config/systemd/user/<name>.{timer,service}`, `systemctl --user daemon-reload`, confirm gone via `list-timers` and `is-enabled`.
4. **Decide the script's fate**: keep it if cited above as a reference implementation; otherwise delete `~/.local/bin/<name>.sh` and drop it from the reference list.
5. **Grep for stragglers**: repo, `~/.local/bin`, and the unit dir for the watcher name; update any docs or issues that still point at it.

Retirement must work over a dirty tree — disarm checks read `origin`, never the working copy.
