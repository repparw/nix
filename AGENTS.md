# Agent guidance

Source of truth: Nix modules, scripts, and tests. Read the relevant source
before proposing or changing behavior. For Den composition, prefer
`includes` for aspects and `imports` for actual Nix module imports; keep
fleet topology in `modules/entities.nix`, shared behavior in aspects, and
host-specific behavior in host modules.

- Never commit plaintext secrets. Use `sops-nix`.
- Use `nh search` for nixpkgs and Home Assistant packages, options, issues, and PRs.
- Check upstream issues before adding a local workaround. For merged fixes,
  verify the exact pinned `flake.lock` revision.

## Documentation policy

**Code and tests describe how the system works.** Do not duplicate host
inventories, service settings, deployment stages, timers, or source-file maps
in Markdown. Routine implementation changes do not require docs edits.

Write Markdown for decisions and non-obvious reasons, constraints that an agent
could otherwise violate, and recovery procedures that must work when the
normal system is unavailable. Update those pages only when the *decision,
safety boundary, or operator procedure* changes. Keep commands next to
the procedure they are needed for, and link to source instead of copying it.
Historical research notes are snapshots, not live configuration references.

Find relevant documentation by task and filename; there is no mandatory
documentation index to synchronize. A missing doc page does not imply that
the feature is absent.

## Agent skills

For proposed config changes, use
[verify-fleet-change](.agents/skills/verify-fleet-change/SKILL.md).
For running-fleet inspection or an authorized activation, use
[fleet-operations](.agents/skills/fleet-operations/SKILL.md).
For upstream waits, use
[watch-upstream](.agents/skills/watch-upstream/SKILL.md).
For web-page change detection, use
[manage-page-watchers](.agents/skills/manage-page-watchers/SKILL.md).

GitHub Issues are the work tracker. Use native sub-issues and dependencies;
check existing labels and issue comments before modifying a ticket. A PR is
not itself a triage request.
