# NixOS Configuration

Personal NixOS and Home Manager configuration based on the upstream `vic/den`
default template.

Hosts:

- `alpha`: desktop workstation with backend services, gaming, streaming, and
  backups.
- `pi`: Raspberry Pi 5 home server with Home Assistant, the LAN HTTPS edge,
  fleet monitoring, and the deployment controller.
- `epsilon`: aarch64 VPS with the public HTTPS edge, Authelia, Miniflux,
  Glance, Hermes, ArchiSteamFarm, and Paperless in nspawn containers.

`beta` is parked: `modules/entities.nix` has no host entry for the laptop.

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
