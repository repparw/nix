{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.archisteamfarm = {
    nixos =
      { config, pkgs, ... }:
      let
        cfg = config.modules.services;
        freepackages = pkgs.callPackage ../../_packages/freepackages.nix { };
        steamPasswordPath = config.sops.secrets.steamPassword.path;
        credentialPasswordPath = "/run/credentials/archisteamfarm.service/steamPassword";
      in
      {
        fileSystems."${cfg.backupDir}/archisteamfarm" = {
          depends = [ "/" ];
          device = "${cfg.configDir}/archisteamfarm";
          fsType = "none";
          options = [
            "bind"
            "ro"
            "nofail"
          ];
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.configDir}/archisteamfarm 0755 root root - -"
        ];

        systemd.services."container@archisteamfarm".after = [
          "home-containers-backup-archisteamfarm.mount"
        ];

        containers.archisteamfarm = {
          autoStart = true;
          privateNetwork = true;
          hostAddress = "10.231.136.1";
          localAddress = "10.231.136.12";
          bindMounts = {
            "/var/lib/archisteamfarm" = {
              hostPath = "${cfg.configDir}/archisteamfarm";
              isReadOnly = false;
            };
            "/run/secrets/steamPassword" = {
              hostPath = steamPasswordPath;
              isReadOnly = true;
            };
          };
          config =
            { ... }:
            {
              services.archisteamfarm = {
                enable = true;
                bots.repparw = {
                  settings.OnlineStatus = 0;
                  username = "ulisesbritos1";
                  passwordFile = credentialPasswordPath;
                };
              };

              systemd.services = {
                archisteamfarm = {
                  serviceConfig.LoadCredential = "steamPassword:/run/secrets/steamPassword";
                  preStart = lib.mkAfter ''
                    [ -e plugins ] && chmod -R u+w plugins && rm -rf plugins
                    cp -rs ${freepackages}/lib/FreePackages plugins/
                  '';
                };
              };

              networking.useHostResolvConf = false;
              networking.nameservers = [ "10.231.136.1" ];
              system.stateVersion = "26.05";
            };
        };
      };
  };
}
