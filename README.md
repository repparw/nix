# NixOS Configuration

Personal NixOS and Home Manager configuration built on the upstream
`vic/den` default-template structure.

## Hosts

- `alpha`: desktop workstation, media services, gaming, streaming, backup jobs.
- `beta`: laptop profile with the shared host baseline plus laptop-specific input,
  power, and display handling.

## Layout

- `flake.nix`: generated flake file. Regenerate it with `nix run .#write-flake`
  after changing `flake-file` inputs.
- `modules/defaults.nix`: repo-wide `den.default` and shared host composition.
- `modules/hosts/`: host aspects.
- `modules/aspects/`: reusable den aspects. Compose these with `includes`.
- `modules/_services/`: NixOS service modules imported by the service aspect.
- `modules/_packages/`: local package definitions and service-only packages.
- `modules/checks.nix`: flake checks.
- `modules/git-hooks.nix`: development shell and pre-commit hooks.
- `knowledge/`: OKF-style knowledge bundle for repo architecture, hosts,
  services, decisions, and runbooks.
- `secrets.yaml`: encrypted `sops-nix` secrets.

## Rules

- Configure generated aspects through `den.aspects.<name>`.
- Use `includes` for aspect composition.
- Use `imports` only for real Nix module imports.
- Put repo-wide defaults in `modules/defaults.nix` via `den.default`.
- Keep related logic together, usually wrapped in the same aspect.
- Put reusable features in dedicated aspect files.
- Do not put plaintext secrets in the repo; use `sops-nix`.

## Commands

```sh
nix flake show
nix flake check
nh os switch
```

## Knowledge

Repo knowledge lives in [knowledge/index.md](knowledge/index.md). It uses
markdown files with YAML frontmatter so the docs stay useful for both humans
and agents.

Start with these runbooks:

- [Failed auto-upgrade rollback](knowledge/runbooks/failed-auto-upgrade-rollback.md)
- [Restore service backups](knowledge/runbooks/restore-service-backups.md)
- [Check native container DNS](knowledge/runbooks/check-native-container-dns.md)

## Operational Backlog

### Medium Priority

- Make host-specific hardware and behavior easier to scan by extracting repeated
  bootloader, filesystem, CPU microcode, and user profile patterns only where
  the abstraction removes actual duplication.
