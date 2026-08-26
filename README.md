# NixOS Configuration

Personal NixOS and Home Manager configuration based on the upstream `vic/den`
default template.

Hosts:

- `alpha`: desktop workstation with backend services, gaming, streaming, and
  backups.
- `pi`: Raspberry Pi 5 home server and public edge (Traefik, Authelia,
  ddclient, Glance, miniflux, ArchisteamFarm, change-detection, Hermes) with
  declarative nspawn containers.

`beta` is parked: its host attachment is commented out in
`modules/aspects/repparw.nix` pending laptop hardware. `pi-sd` is a rescue
SD-image builder, not a host.

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
