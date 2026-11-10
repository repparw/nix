# NixOS infrastructure

Declarative configuration for a three-host Linux fleet spanning a workstation,
a Raspberry Pi home server, and an aarch64 VPS. The repository combines system
configuration, service deployment, monitoring, encrypted backups, and operational
documentation.

## What this demonstrates

- **Infrastructure as code:** NixOS flakes, Home Manager, reusable modules,
  and [deploy-rs](https://github.com/serokell/deploy-rs) for reproducible host
  configuration and deployment.
- **Service operations:** systemd services, systemd-nspawn containers, HTTPS
  ingress, and [Authelia](https://www.authelia.com/) authentication.
- **Observability and recovery:** fleet monitoring in Grafana Cloud, documented
  alerting and troubleshooting, and encrypted offsite backups with Restic.
- **Security and maintenance:** secrets managed with `sops-nix`, distinct
  public and LAN ingress paths, and runbooks for updates, rollback, and recovery.

This is a personal, actively maintained environment rather than a commercial
hosting platform. The repository is public; operational secrets are not.

## Hosts

| Host      | Role                                                                                                                                                      |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `alpha`   | Desktop workstation with backend services, game streaming, and backups                                                                                    |
| `pi`      | Raspberry Pi 5 home server running Home Assistant, LAN HTTPS ingress, fleet monitoring, deployment control, and the free-games claimer                    |
| `epsilon` | aarch64 VPS providing public HTTPS ingress, Authelia, and services including Miniflux, Glance, Hermes, ArchiSteamFarm, and Paperless in nspawn containers |

`beta` is parked: `modules/entities.nix` currently has no host entry for the laptop.

## Explore the implementation

The configuration itself is the reference for current behavior:

- Fleet topology: [entities.nix](modules/entities.nix)
- Shared host composition: [defaults.nix](modules/defaults.nix)
- Service definitions: [services](modules/aspects/services/)
- Deployment controller: [deploy.nix](modules/deploy.nix) and [fleet-update.sh](modules/scripts/fleet-update.sh)

Procedures that cannot be recovered by reading the configuration:

- [Fleet operations and deployment recovery](.agents/skills/fleet-operations/SKILL.md)
- [Offsite host recovery](docs/runbooks/host-recovery.md)
- [Changing persistent storage](docs/runbooks/host-persistence.md)
- [Manual update rollback](docs/runbooks/update-rollback.md)

The configuration started from the upstream `vic/den` template and has since
been adapted for this fleet.

## Local commands

```sh
nix flake show
nix flake check
nh os switch
```

Use the [agent guidance](AGENTS.md) for source-of-truth rules and validation
boundaries.
