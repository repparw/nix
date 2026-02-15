# NixOS Configuration

My personal NixOS configuration files. This repository contains a complete NixOS system configuration using the Nix Flake system.

## Systems
- `alpha`: Desktop configuration
- `beta`: Laptop configuration

## Structure
```shell
.
├── flake.nix         # Main flake configuration
├── overlays/         # Custom package overlays
├── secrets/          # Encrypted secrets
└── systems/          # System configurations
    └── common.nix    # Shared system configuration
```

## Usage

To rebuild the system:
```shell
sudo nixos-rebuild switch --flake .#hostname
```

### VM Testing

Run any system in a VM for testing:
```shell
nix run .#vmAlpha
nix run .#vmBeta
```

Or build the VM image:
```shell
nix build .#vmAlpha
nix build .#vmBeta
```

## Features
- Home Manager integration
- Sops-nix for secret management
- Custom overlays
- Multiple system configurations
