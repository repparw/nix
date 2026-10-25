{ den, ... }:
{
  den.aspects.nodejs-security.nixos.nixpkgs.overlays = [
    (final: prev: {
      bun-security = prev.callPackage ../_packages/bun-security.nix { };
      # Keep the runtime separate: overriding nodejs-slim_24 also rebuilds
      # Electron, QtWebEngine and indirect users of their build tools.
      nodejs-runtime = prev.nodejs_24.override {
        nodejs-slim = prev.callPackage ../_packages/nodejs-security.nix { };
      };
      t3code = prev.t3code.override {
        t3code-unwrapped = prev.t3code.unwrapped.override { nodejs = final.nodejs-runtime; };
      };
    })
  ];
}
