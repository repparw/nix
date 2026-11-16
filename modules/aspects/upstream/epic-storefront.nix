{ den, lib, ... }:
{
  # Epic removed the purchase test ID and checkout wrapper in November 2026.
  # Backport vogler/free-games-claimer#599, including checkout completion.
  # The watcher checks the repository's package source pin before removal.
  # Tolerate an already-fixed pin while its post-lock cleanup PR is pending.
  den.aspects.nixos-services.provides.free-games-claimer.nixos.nixpkgs.overlays = lib.mkAfter [
    (_final: prev: {
      free-games-claimer = prev.free-games-claimer.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace epic-games.js \
            --replace-warn '[data-testid="purchase-cta-button"]' '[class*="sidebarBuyButton"]' \
            --replace-warn '#webPurchaseContainer iframe' 'iframe[src*="/checkout"]'
        '';
      });
    })
  ];
}
