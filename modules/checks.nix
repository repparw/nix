{ inputs, lib, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      checks =
        let
          hosts = lib.attrNames inputs.self.nixosConfigurations;
          hostConfigs = map (host: inputs.self.nixosConfigurations.${host}.config) hosts;
          evalHost =
            host:
            pkgs.runCommand "check-nixos-${host}-eval" { } ''
              printf '%s\n' '${
                inputs.self.nixosConfigurations.${host}.config.system.build.toplevel.drvPath
              }' > $out
            '';
          isGeneratedShellPackage =
            package: lib.isDerivation package && package ? text && package ? checkPhase;
          homePackages = lib.concatMap (
            hostConfig:
            lib.flatten (
              lib.mapAttrsToList (_: userConfig: userConfig.home.packages or [ ]) (
                hostConfig.home-manager.users or { }
              )
            )
          ) hostConfigs;
          generatedShellPackages = lib.filter isGeneratedShellPackage homePackages;
          generatedShellPackageLinks = lib.concatMapStringsSep "\n" (
            package:
            let
              name = builtins.baseNameOf (toString package);
            in
            ''
              ln -sfn ${package} generated-packages/${lib.escapeShellArg name}
            ''
          ) generatedShellPackages;
        in
        {
          formatting =
            pkgs.runCommand "check-formatting"
              {
                nativeBuildInputs = [ config.formatter ];
              }
              ''
                export HOME=$(mktemp -d)
                cp -r ${inputs.self} src
                chmod -R +w src
                cd src
                treefmt --tree-root . --walk filesystem --fail-on-change
                touch $out
              '';

          shellcheck =
            pkgs.runCommand "check-shellcheck"
              {
                nativeBuildInputs = [ pkgs.shellcheck ];
              }
              ''
                cd ${inputs.self}
                find . \( -name '*.sh' -o -name '.envrc' \) -type f -exec shellcheck {} +
                mkdir -p "$TMPDIR/generated-packages"
                cd "$TMPDIR"
                ${generatedShellPackageLinks}
                touch $out
              '';

          service-inventory =
            let
              results = builtins.map (
                host:
                let
                  cfg = inputs.self.nixosConfigurations.${host}.config.modules.services;
                  definitions = lib.attrValues ((cfg.inventory or { }) // (cfg.definitions or { }));
                  ips = lib.filter (x: x != null) (lib.catAttrs "containerAddress" definitions);
                  dups = lib.filter (ip: (builtins.length (builtins.filter (x: x == ip) ips)) > 1) (lib.unique ips);
                in
                if builtins.length dups > 0 then
                  builtins.throw "${host}: duplicate container IPs: ${builtins.concatStringsSep ", " dups}"
                else
                  "${host}: OK"
              ) hosts;
            in
            builtins.seq results (
              pkgs.runCommand "check-service-inventory" { } ''
                {
                  ${lib.concatMapStringsSep "\n" (result: "echo ${lib.escapeShellArg result}") results}
                  echo "service inventory: no duplicate IPs"
                } > $out
              ''
            );

          service-definitions =
            let
              alpha = inputs.self.nixosConfigurations.alpha.config;
              cfg = alpha.modules.services;
              miniflux = cfg.definitions.miniflux;
              paperless = cfg.definitions.paperless;
              authelia = cfg.definitions.authelia;
              glance = cfg.definitions.glance;
              archisteamfarm = cfg.definitions.archisteamfarm;
              automations = cfg.definitions.automations;
              http = alpha.services.traefik.dynamicConfigOptions.http;
              monitorSites = lib.findFirst (
                page: page.name == "Home"
              ) { } alpha.containers.glance.config.services.glance.settings.pages;
              evalDefinition =
                definition:
                builtins.tryEval (
                  (lib.evalModules {
                    modules = [
                      ./service-inventory.nix
                      { modules.services.definitions.invalid = definition; }
                    ];
                  }).config.modules.services.definitions.invalid
                );
              invalidDefinitions = map evalDefinition [
                {
                  hostname = "routed";
                }
                {
                  monitor = true;
                  port = 8080;
                }
                {
                  hostname = "monitored";
                  monitor = true;
                }
              ];
              duplicateMediaAddresses = builtins.tryEval (
                (lib.evalModules {
                  modules = [
                    ./service-inventory.nix
                    {
                      modules.services.definitions = {
                        first.containerAddress = "10.231.136.99";
                        second.containerAddress = "10.231.136.99";
                      };
                    }
                  ];
                }).config.modules.services.definitions
              );
              expectedMediaDefinitions = {
                bazarr = {
                  hostname = "bazarr";
                  containerAddress = "10.231.136.2";
                  port = 6767;
                  auth = "one_factor";
                  backupPath = "${cfg.configDir}/bazarr/backup";
                };
                prowlarr = {
                  hostname = "prowlarr";
                  containerAddress = "10.231.136.3";
                  port = 9696;
                  auth = "one_factor";
                  backupPath = "${cfg.configDir}/prowlarr/Backups";
                };
                qbittorrent = {
                  hostname = "qbit";
                  containerAddress = "10.231.136.4";
                  port = 8080;
                  auth = "external";
                  backupPath = "${cfg.configDir}/qbittorrent";
                };
                radarr = {
                  hostname = "radarr";
                  containerAddress = "10.231.136.5";
                  port = 7878;
                  auth = "one_factor";
                  backupPath = "${cfg.configDir}/radarr/Backups";
                };
                sonarr = {
                  hostname = "sonarr";
                  containerAddress = "10.231.136.6";
                  port = 8989;
                  auth = "one_factor";
                  backupPath = "${cfg.configDir}/sonarr/Backups";
                };
                jellyfin = {
                  hostname = "jellyfin";
                  containerAddress = "10.231.136.10";
                  port = 8096;
                  auth = "bypass";
                  backupPath = "${cfg.configDir}/jellyfin/data/backups";
                };
              };
              hasMonitorSite =
                name: hostname: checkUrl:
                builtins.any (
                  widget:
                  widget.type or null == "monitor"
                  && builtins.any (
                    site:
                    site.title == name && site.url == "https://${hostname}.${cfg.domain}" && site.check-url == checkUrl
                  ) widget.sites
                ) (lib.concatMap (column: column.widgets) monitorSites.columns);
              mediaDefinitionsMatch = lib.all (
                name:
                let
                  expectedService = expectedMediaDefinitions.${name};
                  service = cfg.definitions.${name};
                  endpoint = "http://${expectedService.containerAddress}:${toString expectedService.port}";
                in
                service.hostname == expectedService.hostname
                && service.containerAddress == expectedService.containerAddress
                && service.port == expectedService.port
                && service.auth == expectedService.auth
                && service.monitor
                && service.backup.path == expectedService.backupPath
                && !(builtins.hasAttr name cfg.inventory)
                && alpha.containers.${name}.localAddress == service.containerAddress
                && http.services.${name}.loadBalancer.servers == [ { url = endpoint; } ]
                && hasMonitorSite name expectedService.hostname endpoint
                && alpha.fileSystems."${cfg.backupDir}/${name}".device == expectedService.backupPath
                &&
                  builtins.elem "home-containers-backup-${name}.mount"
                    alpha.systemd.services."container@${name}".after
              ) (lib.attrNames expectedMediaDefinitions);
              expected =
                miniflux.hostname == "rss"
                && miniflux.port == 8081
                && miniflux.auth == "one_factor"
                && miniflux.monitor
                && miniflux.backup.path == "${cfg.configDir}/miniflux"
                && http.routers.miniflux.rule == "Host(`rss.${cfg.domain}`)"
                && http.routers.miniflux.middlewares == [ "authelia" ]
                && http.services.miniflux.loadBalancer.servers == [ { url = "http://127.0.0.1:8081"; } ]
                && hasMonitorSite "miniflux" "rss" "http://127.0.0.1:8081"
                && alpha.fileSystems."${cfg.backupDir}/miniflux".device == "${cfg.configDir}/miniflux"
                && builtins.elem "home-containers-backup-miniflux.mount" alpha.systemd.services.miniflux.after
                && paperless.hostname == "paper"
                && paperless.containerAddress == "10.231.136.12"
                && paperless.port == 8000
                && paperless.auth == "one_factor"
                && paperless.monitor
                && paperless.backup.path == "${cfg.configDir}/paperless/export"
                && alpha.containers.paperless.localAddress == paperless.containerAddress
                && alpha.containers.paperless.bindMounts."/var/lib/paperless".hostPath == "${cfg.configDir}/paper"
                && builtins.elem paperless.port alpha.containers.paperless.config.networking.firewall.allowedTCPPorts
                && alpha.containers.paperless.config.services.paperless.address == "0.0.0.0"
                && alpha.containers.paperless.config.services.paperless.port == paperless.port
                && http.routers.paperless.rule == "Host(`paper.${cfg.domain}`)"
                && http.routers.paperless.middlewares == [ "authelia" ]
                && http.services.paperless.loadBalancer.servers == [ { url = "http://10.231.136.12:8000"; } ]
                && hasMonitorSite "paperless" "paper" "http://10.231.136.12:8000"
                && alpha.fileSystems."${cfg.backupDir}/paperless".device == paperless.backup.path
                &&
                  builtins.elem "home-containers-backup-paperless.mount"
                    alpha.systemd.services."container@paperless".after
                && authelia.hostname == "auth"
                && authelia.containerAddress == "10.231.136.7"
                && authelia.port == 9091
                && authelia.auth == "bypass"
                && authelia.monitor
                && authelia.backup.path == "${cfg.configDir}/authelia"
                && !(cfg.inventory ? authelia)
                && alpha.containers.authelia.localAddress == authelia.containerAddress
                && builtins.elem authelia.port alpha.containers.authelia.config.networking.firewall.allowedTCPPorts
                &&
                  alpha.containers.authelia.config.services.authelia.instances.main.settings.server.address
                  == "tcp://:${toString authelia.port}"
                && http.routers.authelia.rule == "Host(`auth.${cfg.domain}`)"
                && !(http.routers.authelia ? middlewares)
                && http.services.authelia.loadBalancer.servers == [ { url = "http://10.231.136.7:9091"; } ]
                &&
                  http.middlewares.authelia.forwardAuth.address == "http://10.231.136.7:9091/api/authz/forward-auth"
                && hasMonitorSite "authelia" "auth" "http://10.231.136.7:9091"
                && alpha.fileSystems."${cfg.backupDir}/authelia".device == authelia.backup.path
                && glance.containerAddress == "10.231.136.15"
                && glance.port == 8080
                && glance.auth == "bypass"
                && !(cfg.inventory ? glance)
                && alpha.containers.glance.localAddress == glance.containerAddress
                && alpha.containers.glance.config.services.glance.settings.server.host == "0.0.0.0"
                && alpha.containers.glance.config.services.glance.settings.server.port == glance.port
                && http.routers.glance.rule == "Host(`${cfg.domain}`)"
                && http.services.glance.loadBalancer.servers == [ { url = "http://10.231.136.15:8080"; } ]
                && alpha.containers.glance.config.services.glance.settings.branding.logo-text == "R"
                && archisteamfarm.containerAddress == "10.231.136.13"
                && archisteamfarm.hostname == null
                && archisteamfarm.port == null
                && archisteamfarm.auth == "bypass"
                && !archisteamfarm.monitor
                && archisteamfarm.backup.path == "${cfg.configDir}/archisteamfarm"
                && !(cfg.inventory ? archisteamfarm)
                && alpha.containers.archisteamfarm.localAddress == archisteamfarm.containerAddress
                &&
                  alpha.containers.archisteamfarm.bindMounts."/var/lib/archisteamfarm".hostPath
                  == archisteamfarm.backup.path
                &&
                  alpha.containers.archisteamfarm.config.systemd.services.archisteamfarm.serviceConfig.LoadCredential
                  == "steamPassword:/run/secrets/steamPassword"
                && alpha.fileSystems."${cfg.backupDir}/archisteamfarm".device == archisteamfarm.backup.path
                &&
                  builtins.elem "home-containers-backup-archisteamfarm.mount"
                    alpha.systemd.services."container@archisteamfarm".after
                && automations.hostname == null
                && automations.containerAddress == null
                && automations.port == null
                && automations.auth == "bypass"
                && !automations.monitor
                && automations.backup.path == "${cfg.configDir}/automations"
                && !(cfg.inventory ? automations)
                && alpha.fileSystems."${cfg.backupDir}/automations".device == automations.backup.path
                && !(builtins.hasAttr "container@automations" alpha.systemd.services)
                && alpha.systemd.timers.change-detection.timerConfig.OnCalendar == "*-*-* 00/6:13:00"
                && alpha.systemd.timers.change-detection.timerConfig.RandomizedDelaySec == "5min"
                && mediaDefinitionsMatch
                && http.routers.bazarr.middlewares == [ "authelia" ]
                && http.routers.prowlarr.middlewares == [ "authelia" ]
                && http.routers.radarr.middlewares == [ "authelia" ]
                && http.routers.sonarr.middlewares == [ "authelia" ]
                && !(http.routers.jellyfin ? middlewares)
                && http.routers.qbittorrent.rule == "Host(`qbit.${cfg.domain}`) && !PathPrefix(`/api`)"
                && http.routers.qbittorrent-api.rule == "Host(`qbit.${cfg.domain}`) && PathPrefix(`/api`)"
                &&
                  alpha.containers.qbittorrent.forwardPorts == [
                    {
                      protocol = "tcp";
                      hostPort = 54535;
                      containerPort = 54535;
                    }
                    {
                      protocol = "udp";
                      hostPort = 54535;
                      containerPort = 54535;
                    }
                  ]
                && lib.all (name: alpha.containers.${name}.privateUsers == "identity") [
                  "bazarr"
                  "prowlarr"
                  "qbittorrent"
                  "radarr"
                  "sonarr"
                ]
                && alpha.containers.jellyfin.privateUsers == "pick"
                && alpha.containers.radarr.bindMounts."/data".hostPath == cfg.mediaPortalDir
                && alpha.containers.radarr.bindMounts."/config".hostPath == "${cfg.configDir}/radarr"
                && alpha.containers.radarr.bindMounts."/data/torrents".hostPath == "${cfg.rootDir}/torrents"
                && alpha.containers.sonarr.bindMounts."/data".hostPath == cfg.mediaPortalDir
                && alpha.containers.sonarr.bindMounts."/config".hostPath == "${cfg.configDir}/sonarr"
                &&
                  alpha.containers.prowlarr.bindMounts."/var/lib/private/prowlarr/Backups".hostPath
                  == "${cfg.configDir}/prowlarr/Backups"
                &&
                  alpha.containers.qbittorrent.bindMounts."/var/lib/qBittorrent/qBittorrent".hostPath
                  == "${cfg.configDir}/qbittorrent"
                && alpha.containers.qbittorrent.bindMounts."/data/torrents".hostPath == "${cfg.rootDir}/torrents"
                && alpha.containers.qbittorrent.config.services.qbittorrent.torrentingPort == 54535
                && alpha.containers.radarr.config.services.radarr.settings.server.bindAddress == "*"
                && alpha.containers.radarr.config.services.radarr.dataDir == "/config"
                && alpha.containers.jellyfin.bindMounts."/var/lib/jellyfin".hostPath == "${cfg.configDir}/jellyfin"
                && alpha.containers.jellyfin.bindMounts."/data".hostPath == cfg.mediaPortalDir
                &&
                  map (device: device.node) alpha.containers.jellyfin.allowedDevices == [
                    "/dev/dri/renderD128"
                    "/dev/dri/card0"
                    "/dev/dri/card1"
                  ]
                && alpha.systemd.services."container@jellyfin".serviceConfig.CPUQuota == "300%"
                && alpha.systemd.services."container@jellyfin".serviceConfig.IOWeight == 50
                && alpha.systemd.services."container@jellyfin".serviceConfig.Nice == 10
                && builtins.all (result: !result.success) invalidDefinitions
                && !duplicateMediaAddresses.success;
            in
            assert expected;
            pkgs.runCommand "check-service-definitions" { } ''
              echo "service definitions: valid derivation and invalid combination verified" > $out
            '';
        }
        // lib.genAttrs hosts evalHost;
    };
}
