{ den, ... }:
{
  den.aspects.ai.provides.opencode-v2 = {
    nixos.nixpkgs.overlays = [
      (final: _prev: {
        opencode-v2 = final.callPackage ../../_packages/opencode-v2.nix { };
      })
    ];
    homeManager =
      { config, pkgs, ... }:
      {
        xdg.configFile = {
          "opencode-v2/opencode/opencode.json".source =
            pkgs.runCommandLocal "opencode-v2-config.json" { nativeBuildInputs = [ pkgs.jq ]; }
              ''
                jq 'del(."$schema") | .plugin = []' \
                  ${config.xdg.configFile."opencode/opencode.json".source} > "$out"
              '';
          "opencode-v2/opencode/plugins/nous-live.ts".source = ./opencode-plugins/nous-live-v2.ts;
          "opencode-v2/opencode/skills".source =
            config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/opencode/skills";
          "opencode-v2/opencode/AGENTS.md".source =
            config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/opencode/AGENTS.md";
        };
      };
  };
  perSystem = { pkgs, ... }: {
    packages.opencode-v2 = pkgs.callPackage ../../_packages/opencode-v2.nix { };
  };
}
