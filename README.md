# NixOS Configuration

Personal NixOS and Home Manager configuration based on the upstream `vic/den`
default template.

Hosts:

- `alpha`: desktop workstation with services, gaming, streaming, and backups.
- `beta`: laptop profile with shared defaults and laptop-specific hardware.

## Commands

```sh
nix flake show
nix flake check
nh os switch
```

## Docs

See the [documentation index](docs/index.md) for architecture, host profiles,
services, runbooks, and research notes. Source-specific conventions live with
the relevant architecture page; secrets are encrypted with `sops-nix`.
