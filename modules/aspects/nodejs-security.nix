{ den, ... }:
{
  den.aspects.nodejs-security.nixos.nixpkgs.overlays = [
    (_final: prev: {
      bun-security = prev.callPackage ../_packages/bun-security.nix { };
      # Nixpkgs#576777 and #576792 have not reached our nixos-unstable pin.
      # Keep the security dependencies private to Node to avoid a fleet-wide
      # OpenSSL/Brotli rebuild. Electron bundles its own libraries separately.
      nodejs-slim_24 = prev.callPackage ../_packages/nodejs-security.nix {
        inherit (prev) nodejs-slim_24;
      };
    })
  ];
}
