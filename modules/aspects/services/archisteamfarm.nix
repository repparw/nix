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
        servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
        freepackages = pkgs.callPackage ../../_packages/freepackages.nix { };
        steamPasswordPath = config.sops.secrets.steamPassword.path;
        credentialPasswordPath = "/run/credentials/archisteamfarm.service/steamPassword";
      in
      {
        systemd.tmpfiles.rules = [
          "d ${cfg.configDir}/archisteamfarm 0755 root root - -"
        ];

        modules.services.inventory.archisteamfarm = {
          containerAddress = "10.231.136.13";
          auth = "bypass";
          backup.path = "${cfg.configDir}/archisteamfarm";
        };

        containers.archisteamfarm = servicesLib.mkContainer {
          inherit cfg;
          name = "archisteamfarm";
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
          extraConfig = {
            services.archisteamfarm = {
              enable = true;
              bots.repparw = {
                settings = {
                  OnlineStatus = 0;
                  EnableFreePackages = true;
                  PauseFreePackagesWhilePlaying = true;
                  FreePackagesFilters = [
                    {
                      NoCostOnly = true;
                    }
                    {
                      Categories = [ 29 ];
                    }
                    {
                      Types = [ "DLC" ];
                      IgnoredTypes = [ "Game" "Application" ];
                    }
                  ];
                };
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
          };
        };
      };
  };
}
