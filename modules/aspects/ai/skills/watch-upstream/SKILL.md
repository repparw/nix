---
description: Use for "watch until upstream lands", "when nixpkgs/home-manager PR X merges", "unblock when upstream", "remove the vendored workaround after", or any blocked-on-upstream cleanup: set an autonomous probe that completes the unblock (bump pin, drop workaround, merge the stacked PR) without human intervention.
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

Restructure first if needed: vendored code gets its own file/provide included by single lines from every consumer, so completion is `git rm` plus deleting include lines, never regex surgery.

## The probe

No cron on this machine. Systemd user pair in `~/.config/systemd/user/`: `<name>.service` (`Type=oneshot`, `ExecStart=<script>`) and `<name>.timer` (`OnCalendar=*-*-* 00/2:17:00`, **`Persistent=true`**, `WantedBy=timers.target`). Then enable and start it. Two hours is plenty; faster buys nothing.

The script goes in `~/.local/bin/<name>.sh`, never in the repo. Hardcode `REPO="$HOME/Projects/nix"`.

## Script contract

Every watcher must satisfy all five:

1. **Quiet while waiting**: not-ready prints one line, exits 0. Non-zero there pollutes journals.
2. **Idempotent**: detect "already done" and disable the timer instead of redoing work.
3. **Narrow writes**: stage only files the unblock owns. Refuse to run over a dirty tracked tree.
4. **Gate before pushing**: after detection, run what breaks if you guessed wrong (flake update then eval every host; build the unpatched package). Gate failure means revert local state untouched, exit non-zero, notify. Detection alone is not permission to act.
5. **Self-disarming**: full success disables the timer.

Bash/awk only; python3 is not on systemd's default PATH. Gotchas: gawk treats `-v var="123"` as a string, so write `NR > (s + 0)` or line comparisons match lexicographically; flakes only see git-tracked files, so stage new workaround files before any eval against the tree.

## Verify armed, report

Run the script once by hand (expect the not-ready path), confirm `list-timers` shows the next fire. Report: what is watched, the condition, what happens automatically, where logs live (`journalctl --user -u <name>`), and that the probe survives restarts.

Reference implementations (machine-local): `~/.local/bin/watch-moonshine.sh`, `watch-t3code-title-fix.sh`, `watch-tasks-org.sh`, `watch-qbittorrent.sh`, `watch-t3code-server.sh`, `watch-t3code-split.sh`.
