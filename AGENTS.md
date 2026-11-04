Before changing Nix aspects, composition, defaults, or file placement, read
[Den aspect composition](docs/architecture/den-aspect-composition.md).

- Do not put plaintext secrets in repo; use `sops-nix`.

Use `nh search` for packages, options, issues and PRs on nixpkgs/home-assistant

Check issues before implementing a local workaround. For merged fixes, verify containment in the exact input revision pinned by `flake.lock`.

## Agent skills

For configuration changes or pre-deployment checks, use
[verify-fleet-change](.agents/skills/verify-fleet-change/SKILL.md). For
running-fleet inspection or an authorized activation, use
[fleet-operations](.agents/skills/fleet-operations/SKILL.md). For an external
change blocked on an upstream input, use
[watch-upstream](.agents/skills/watch-upstream/SKILL.md).
For web-page change detection in the automations service, use
[manage-page-watchers](.agents/skills/manage-page-watchers/SKILL.md).

For issues and PRDs, read [issue tracker](docs/agents/issue-tracker.md).
For triage and labels, read [triage labels](docs/agents/triage-labels.md).
For domain modeling or design decisions, read [domain docs](docs/agents/domain.md).

### Documentation routing

Select task context through [docs/index.md](docs/index.md), using candidate pages'
`when`, `type`, `tags`, and `resource` frontmatter. Read matching pages and follow
relevant source and related links.
