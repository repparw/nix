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

| Host | Role |
| --- | --- |
| `alpha` | Desktop workstation with backend services, game streaming, and backups |
| `pi` | Raspberry Pi 5 home server running Home Assistant, LAN HTTPS ingress, fleet monitoring, and deployment control |
| `epsilon` | aarch64 VPS providing public HTTPS ingress, Authelia, and services including Miniflux, Glance, Hermes, ArchiSteamFarm, and Paperless in nspawn containers |

`beta` is parked: `modules/entities.nix` currently has no host entry for the laptop.

## Explore the implementation

- [Architecture and repository layout](docs/index.md)
- [Host profiles](docs/hosts.md)
- [Fleet operations](docs/runbooks/fleet-operations.md)
- [Monitoring and troubleshooting](docs/runbooks/monitoring.md)
- [Update and rollback](docs/runbooks/update-rollback.md)
- [Backup restoration](docs/runbooks/restore-service-backups.md)
- [Host recovery](docs/runbooks/host-recovery.md)
- [Grafana Cloud dashboards and operations](https://github.com/repparw/grafana)
- [TP-Link Terraform/OpenTofu provider](https://github.com/repparw/terraform-provider-tplink)

The configuration started from the upstream `vic/den` template and has since
been adapted for this fleet.

## Local commands

```sh
nix flake show
nix flake check
nh os switch
```

See the [documentation index](docs/index.md) for service-specific procedures
and verification steps. Deployment and restoration depend on host-specific
permissions, encrypted secrets, and the corresponding runbooks.
