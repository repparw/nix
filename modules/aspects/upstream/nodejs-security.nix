{ den, ... }:
{
  den.aspects.nodejs-security.nixos.nixpkgs.overlays = [
    (final: prev: {
      bun-security = prev.callPackage ../../_packages/bun-security.nix { };
      # Keep the runtime separate: overriding nodejs-slim_24 also rebuilds
      # Electron, QtWebEngine and indirect users of their build tools.
      nodejs-runtime = prev.nodejs_24.override {
        nodejs-slim = prev.callPackage ../../_packages/nodejs-security.nix { };
      };
      # T3 Code 0.1.5 uses Node 26 directly, and its unwrapped package no
      # longer accepts the old `nodejs` argument. Keep our pinned secure
      # Node 24 runtime only for older packages that still use that argument.
      t3code =
        if prev.lib.versionAtLeast prev.t3code.unwrapped.version "0.1.5" then
          prev.t3code
        else
          prev.t3code.override {
            t3code-unwrapped = prev.t3code.unwrapped.override { nodejs = final.nodejs-runtime; };
          };
    })
  ];
}
