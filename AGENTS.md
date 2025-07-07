# Agent Instructions

## Commands
- Build: `nixos-rebuild build --flake .#`
- Test single host: `nixos-rebuild build --flake .#hostname`
- Check config: `nix flake check`
- Format code: `nixfmt **/*.nix`

## Code Style
- Use 2-space indentation in .nix files
- Keep imports at the top of the file, sorted alphabetically
- Use explicit types for function parameters
- Prefer `mkOption` over direct attribute sets for module options
- Use descriptive names for variables and functions (no abbreviations)
- Follow the nixpkgs naming convention for packages
- Error handling: Use assertions for critical checks
- Document non-obvious configuration options
- Keep modules focused and composable
- Use relative imports within modules/
- Place service configurations in modules/services/
- Separate GUI and CLI configurations in respective directories