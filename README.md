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

## Recovery Runbook

### Failed Auto-Upgrade Rollback

Auto-upgrade is enabled through `den.aspects.auto-upgrade` and updates every
flake input with `--commit-lock-file`.

1. Inspect the failed run:

   ```sh
   systemctl status nixos-upgrade.service
   journalctl -u nixos-upgrade.service -b
   git status
   git log --oneline -5
   ```

2. Boot or switch back to the previous working generation:

   ```sh
   sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
   sudo /nix/var/nix/profiles/system-<generation>-link/bin/switch-to-configuration switch
   ```

3. If auto-upgrade committed a bad lock update, revert that commit or restore
   the previous `flake.lock`, then verify before switching again:

   ```sh
   nix flake check
   nh os switch
   ```

### Restore Service Backups

Service backup exports are gathered under `modules.services.backupDir`, which
defaults to `/home/containers/backup`. Most service backup paths are read-only
bind mounts from `/home/containers/config`.

1. Find the backup source and stop the affected service:

   ```sh
   ls -lah /home/containers/backup
   systemctl stop container@<service>.service
   ```

   For native host services, use the service unit directly, for example
   `systemctl stop miniflux.service`.

2. Restore into the live config path under `/home/containers/config/<service>`.
   Preserve owners, modes, and existing path layout. For database dumps such as
   Miniflux, restore through the database tooling instead of copying the dump
   over the live data directory.

3. Start the service and inspect logs:

   ```sh
   systemctl start container@<service>.service
   journalctl -u container@<service>.service -b
   ```

### Check Native Container DNS

Private containers use `networking.useHostResolvConf = false` and resolve
through the host bridge at `10.231.136.1`. The host exposes `systemd-resolved`
with `DNSStubListenerExtra = "0.0.0.0"`.

1. Check host-side DNS first:

   ```sh
   resolvectl status
   ss -lunpt | rg ':53'
   systemctl status systemd-resolved.service
   ```

2. Check the container resolver and a known lookup:

   ```sh
   sudo nixos-container run <service> -- cat /etc/resolv.conf
   sudo nixos-container run <service> -- getent hosts cache.nixos.org
   sudo nixos-container run <service> -- resolvectl query cache.nixos.org
   ```

3. If lookup fails, verify the container still points at `10.231.136.1`, the
   host firewall accepts `ve-*` DNS traffic, and
   `services.resolved.settings.Resolve.DNSStubListenerExtra` is still enabled.

## Operational Backlog

### High Priority

- Keep service migrations data-first. When converting a container or service,
  inspect the live config/data tree first and preserve the path mapping in Nix.

### Medium Priority

- Add service smoke checks for the media stack: render Traefik routers, Glance
  monitor URLs, and container addresses from one shared service inventory so
  names cannot drift independently across `_services/proxy.nix`,
  `_services/glance.nix`, and `modules/aspects/services.nix`.
- Make host-specific hardware and behavior easier to scan by extracting repeated
  bootloader, filesystem, CPU microcode, and user profile patterns only where
  the abstraction removes actual duplication.

### Low Priority

- Add descriptions to flake apps so `nix flake show` is more self-documenting.
