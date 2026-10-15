{ lib, ... }:
{
  den.aspects.nixos-services.provides.arr.nixos =
    { config, ... }:
    {
      modules.backup.exports = lib.genAttrs [ "sonarr" "radarr" "prowlarr" "bazarr" ] (name: {
        path =
          config.modules.services.definitions.${name}.backup.path
          + lib.optionalString (name != "bazarr") "/scheduled";
        pattern = "${name}_backup_*.zip";
        maxAgeSeconds = 26 * 60 * 60;
      });
    };
}
