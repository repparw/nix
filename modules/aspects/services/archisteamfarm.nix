{
  den,
  lib,
  ...
}:
{
  den.aspects.nixos-services.provides.archisteamfarm = {
    service-registry = {
      name = "archisteamfarm";
      definition = {
        auth = "bypass";
        container = true;
        backupRelativePath = "archisteamfarm";
      };
    };

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
        sops.secrets.steamPassword = {
          sopsFile = ../../../secrets/archisteamfarm.sops.yaml;
          owner = "root";
          mode = "0400";
        };

        sops.secrets.steamUsername = {
          sopsFile = ../../../secrets/archisteamfarm.sops.yaml;
          owner = "root";
          mode = "0400";
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.configDir}/archisteamfarm 0755 root root - -"
        ];

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
            "/run/secrets/steamUsername" = {
              hostPath = config.sops.secrets.steamUsername.path;
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
                      Types = [ "DLC" ];
                      IgnoredTypes = [
                        "Game"
                        "Application"
                      ];
                    }
                  ];
                };
                # Substituted at runtime by `replace-secret` in the preStart
                # below; ASF only accepts a literal string for SteamLogin.
                username = "#steamUsername#";
                passwordFile = credentialPasswordPath;
              };
            };

            systemd.services = {
              archisteamfarm = {
                serviceConfig.LoadCredential = [
                  "steamPassword:/run/secrets/steamPassword"
                  "steamUsername:/run/secrets/steamUsername"
                ];
                preStart = lib.mkAfter ''
                  [ -e plugins ] && chmod -R u+w plugins && rm -rf plugins
                  cp -rs ${freepackages}/lib/FreePackages plugins/
                  botConfig=$(mktemp config/.repparw.XXXXXX)
                  trap 'rm -f "$botConfig"' EXIT
                  cp --no-preserve=mode config/repparw.json "$botConfig"
                  ${pkgs.replace-secret}/bin/replace-secret '#steamUsername#' "$CREDENTIALS_DIRECTORY/steamUsername" "$botConfig"
                  mv -f "$botConfig" config/repparw.json
                '';
              };
            };
          };
        };
      };
  };
}
