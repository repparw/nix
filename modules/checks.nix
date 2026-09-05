{ inputs, lib, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      checks =
        let
          hosts = lib.attrNames inputs.self.nixosConfigurations;
          evalHost =
            host:
            let
              evaluatedDrvPath = builtins.unsafeDiscardStringContext (
                inputs.self.nixosConfigurations.${host}.config.system.build.toplevel.drvPath
              );
            in
            pkgs.runCommand "check-nixos-${host}-eval" { } ''
              printf '%s\n' ${lib.escapeShellArg evaluatedDrvPath} > $out
            '';
          isGeneratedShellPackage =
            package:
            lib.isDerivation package && package ? text && package ? checkPhase && package.executable or false;
          packageRecord = source: package: {
            label = "${source}:${package.meta.mainProgram or package.name}";
            script = pkgs.writeText "${package.meta.mainProgram or package.name}-generated.sh" ''
              #!${pkgs.runtimeShell}
              ${builtins.unsafeDiscardStringContext package.text}
            '';
          };
          homePackageRecords = lib.concatMap (
            host:
            lib.concatLists (
              lib.mapAttrsToList (
                user: userConfig:
                map (packageRecord "home:${host}:${user}") (
                  lib.filter isGeneratedShellPackage (lib.flatten (userConfig.home.packages or [ ]))
                )
              ) (inputs.self.nixosConfigurations.${host}.config.home-manager.users or { })
            )
          ) hosts;
          flakePackageRecords = lib.mapAttrsToList (name: package: packageRecord "flake:${name}" package) (
            lib.filterAttrs (_: isGeneratedShellPackage) config.packages
          );
          generatedShellRecords = homePackageRecords ++ flakePackageRecords;
          generatedShellsByScript = lib.foldl' (
            scripts: record:
            let
              key = builtins.unsafeDiscardStringContext record.script;
              previous =
                scripts.${key} or {
                  inherit (record) script;
                  labels = [ ];
                };
            in
            scripts
            // {
              ${key} = previous // {
                labels = previous.labels ++ [ record.label ];
              };
            }
          ) { } generatedShellRecords;
          generatedShellChecks = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              _: entry:
              let
                description = lib.concatStringsSep ", " (lib.sort builtins.lessThan (lib.unique entry.labels));
              in
              ''
                printf 'ShellCheck generated application: %s\n' ${lib.escapeShellArg description}
                if ! shellcheck ${lib.escapeShellArg entry.script}; then
                  printf 'ShellCheck failed for generated application: %s (%s)\n' \
                    ${lib.escapeShellArg description} ${lib.escapeShellArg entry.script} >&2
                  exit 1
                fi
              ''
            ) generatedShellsByScript
          );
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
                ${generatedShellChecks}
                touch $out
              '';

          sops-files = pkgs.runCommand "check-sops-files" { } ''
            invalid_names=$(find ${inputs.self}/secrets -maxdepth 1 -type f -name '*.yaml' ! -name '*.sops.yaml' -print)
            missing_metadata=$(find ${inputs.self}/secrets -maxdepth 1 -type f -name '*.sops.yaml' ! -exec grep -q '^sops:$' {} \; -print)

            if [ -n "$invalid_names" ]; then
              printf 'SOPS YAML files must use the .sops.yaml suffix:\n%s\n' "$invalid_names" >&2
              exit 1
            fi

            if [ -n "$missing_metadata" ]; then
              printf 'Files with the .sops.yaml suffix must contain SOPS metadata:\n%s\n' "$missing_metadata" >&2
              exit 1
            fi

            touch $out
          '';

          change-detection =
            pkgs.runCommand "check-change-detection"
              {
                nativeBuildInputs = [ pkgs.nodejs ];
              }
              ''
                node ${./aspects/services/automations}/change-detection.test.mjs
                touch $out
              '';

          service-definitions =
            let
              alpha = inputs.self.nixosConfigurations.alpha.config;
              pi = inputs.self.nixosConfigurations.pi.config;
              epsilon = inputs.self.nixosConfigurations.epsilon.config;
              cfg = alpha.modules.services;
              edgeCfg = epsilon.modules.services;
              servicesLib = import ./_services/lib.nix { inherit lib pkgs; };
              miniflux = edgeCfg.definitions.miniflux;
              paperless = cfg.definitions.paperless;
              authelia = edgeCfg.definitions.authelia;
              glance = edgeCfg.definitions.glance;
              archisteamfarm = edgeCfg.definitions.archisteamfarm;
              automations = edgeCfg.definitions.automations;
              http = epsilon.services.traefik.dynamicConfigOptions.http;
              accessControl =
                epsilon.containers.authelia.config.services.authelia.instances.main.settings.access_control;
              monitorSites = lib.findFirst (
                page: page.name == "Home"
              ) { } epsilon.containers.glance.config.services.glance.settings.pages;
              evalDefinition =
                definition:
                builtins.tryEval (
                  (lib.evalModules {
                    modules = [
                      ./service-definitions.nix
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
                {
                  hostname = "";
                  port = 8080;
                }
                {
                  hostname = "invalid.example";
                  port = 8080;
                }
                {
                  healthcheck = "/healthcheck";
                }
              ];
              duplicateHostnames = builtins.tryEval (
                (lib.evalModules {
                  modules = [
                    ./service-definitions.nix
                    {
                      modules.services.definitions = {
                        first = {
                          hostname = "same";
                          port = 8080;
                        };
                        second = {
                          hostname = "same";
                          port = 8081;
                        };
                      };
                    }
                  ];
                }).config.modules.services.definitions
              );
              mkIngressPolicy = import ./_services/ingress-policy.nix { inherit lib; };
              matrixPolicy = mkIngressPolicy {
                domain = "example.test";
                serviceUrl = name: "http://${name}";
                definitions = {
                  bypass = {
                    hostname = "bypass";
                    port = 1000;
                    auth = "bypass";
                  };
                  one = {
                    hostname = "one";
                    port = 1001;
                    auth = "one_factor";
                  };
                  two = {
                    hostname = "two";
                    port = 1002;
                    auth = "two_factor";
                  };
                };
              };
              unsupportedExternal = builtins.tryEval (
                (mkIngressPolicy {
                  domain = "example.test";
                  serviceUrl = name: "http://${name}";
                  definitions.unsupported = {
                    hostname = "unsupported";
                    port = 1003;
                    auth = "external";
                  };
                }).traefik
              );
              sparsePolicy = mkIngressPolicy {
                domain = "example.test";
                serviceUrl = name: "http://${name}";
                definitions.paperless = {
                  hostname = null;
                  port = null;
                  auth = "bypass";
                };
              };
              expectedMediaDefinitions = {
                bazarr = {
                  hostname = "bazarr";
                  localAddress = "10.231.136.2";
                  port = 6767;
                  auth = "one_factor";
                  backupPath = "${cfg.configDir}/bazarr/backup";
                };
                prowlarr = {
                  hostname = "prowlarr";
                  localAddress = "10.231.136.5";
                  port = 9696;
                  auth = "one_factor";
                  backupPath = "${cfg.configDir}/prowlarr/Backups";
                };
                qbittorrent = {
                  hostname = "qbit";
                  localAddress = "10.231.136.6";
                  port = 8080;
                  publishedPort = 18080;
                  auth = "external";
                  backupPath = "${cfg.configDir}/qbittorrent";
                };
                radarr = {
                  hostname = "radarr";
                  localAddress = "10.231.136.7";
                  port = 7878;
                  auth = "one_factor";
                  backupPath = "${cfg.configDir}/radarr/Backups";
                };
                sonarr = {
                  hostname = "sonarr";
                  localAddress = "10.231.136.8";
                  port = 8989;
                  auth = "one_factor";
                  backupPath = "${cfg.configDir}/sonarr/Backups";
                };
                jellyfin = {
                  hostname = "jellyfin";
                  localAddress = "10.231.136.3";
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
                in
                service.hostname == expectedService.hostname
                && service.port == expectedService.port
                && service.auth == expectedService.auth
                && service.monitor
                && service.backup.path == expectedService.backupPath
                && alpha.containers.${name}.localAddress == expectedService.localAddress
                && hasMonitorSite name expectedService.hostname (
                  if service.healthcheck != null then
                    servicesLib.publicHealthUrl edgeCfg epsilon name
                  else
                    servicesLib.serviceUrl edgeCfg epsilon name
                )
                && alpha.fileSystems."${cfg.backupDir}/${name}".device == expectedService.backupPath
                &&
                  builtins.elem "home-containers-backup-${name}.mount"
                    alpha.systemd.services."container@${name}".after
              ) (lib.attrNames expectedMediaDefinitions);
              nativeServicesMatch =
                edgeCfg ? definitions.homeassistant
                # Miniflux + its PostgreSQL run in an nspawn container,
                # reached over the bridge like the rest.
                && miniflux.hostname == "rss"
                && miniflux.port == 8081
                && miniflux.auth == "one_factor"
                && miniflux.monitor
                && miniflux.backup.path == "${edgeCfg.configDir}/miniflux"
                && epsilon.containers.miniflux.localAddress == "10.231.137.5"
                && epsilon.containers.miniflux.config.services.miniflux.enable
                && epsilon.containers.miniflux.config.services.postgresql.enable
                &&
                  epsilon.containers.miniflux.bindMounts."/var/lib/postgresql".hostPath
                  == "${edgeCfg.configDir}/miniflux/postgresql"
                && hasMonitorSite "miniflux" "rss" (servicesLib.publicHealthUrl edgeCfg epsilon "miniflux")
                && paperless.hostname == "paper"
                && paperless.port == 8000
                && paperless.auth == "one_factor"
                && paperless.monitor
                && paperless.backup.path == "${cfg.configDir}/paperless/export"
                && alpha.containers.paperless.localAddress == "10.231.136.4"
                && alpha.containers.paperless.bindMounts."/var/lib/paperless".hostPath == "${cfg.configDir}/paper"
                && builtins.elem paperless.port alpha.containers.paperless.config.networking.firewall.allowedTCPPorts
                && alpha.containers.paperless.config.services.paperless.address == "0.0.0.0"
                && alpha.containers.paperless.config.services.paperless.port == paperless.port
                && hasMonitorSite "paperless" "paper" (servicesLib.serviceUrl edgeCfg epsilon "paperless")
                && alpha.fileSystems."${cfg.backupDir}/paperless".device == paperless.backup.path
                &&
                  builtins.elem "home-containers-backup-paperless.mount"
                    alpha.systemd.services."container@paperless".after;
              authenticationPresentationMatch =
                authelia.hostname == "auth"
                && authelia.port == 9091
                && authelia.auth == "bypass"
                && authelia.monitor
                && epsilon.containers.authelia.localAddress == "10.231.137.2"
                && builtins.elem authelia.port epsilon.containers.authelia.config.networking.firewall.allowedTCPPorts
                &&
                  epsilon.containers.authelia.config.services.authelia.instances.main.settings.server.address
                  == "tcp://:${toString authelia.port}"
                && glance.port == 8080
                && glance.auth == "bypass"
                && epsilon.containers.glance.localAddress == "10.231.137.3"
                && epsilon.containers.glance.config.services.glance.settings.server.host == "0.0.0.0"
                && epsilon.containers.glance.config.services.glance.settings.server.port == glance.port
                && http.routers.glance.rule == "Host(`${cfg.domain}`)"
                && epsilon.containers.glance.config.services.glance.settings.branding.logo-text == "R";
              backgroundServicesMatch =
                # Archisteamfarm farms on pi (always-on host); its definition
                # and container live in pi's closure.
                archisteamfarm.hostname == null
                && archisteamfarm.port == null
                && archisteamfarm.auth == "bypass"
                && !archisteamfarm.monitor
                && archisteamfarm.backup.path == "${cfg.configDir}/archisteamfarm"
                && pi.containers.archisteamfarm.localAddress == "10.231.136.2"
                &&
                  pi.containers.archisteamfarm.bindMounts."/var/lib/archisteamfarm".hostPath
                  == archisteamfarm.backup.path
                &&
                  pi.containers.archisteamfarm.config.systemd.services.archisteamfarm.serviceConfig.LoadCredential
                  == "steamPassword:/run/secrets/steamPassword"
                && builtins.any (lib.strings.hasInfix "archisteamfarm") pi.systemd.tmpfiles.rules
                && automations.hostname == null
                && automations.port == null
                && automations.auth == "bypass"
                && !automations.monitor
                && automations.backup.path == "${edgeCfg.configDir}/automations"
                # Automations is a pi-native oneshot: no
                # nspawn container on either host, state dir via tmpfiles,
                # six-hour timer local to the edge.
                && builtins.any (lib.strings.hasInfix "automations") pi.systemd.tmpfiles.rules
                && !(builtins.hasAttr "container@automations" alpha.systemd.services)
                && !(builtins.hasAttr "container@automations" pi.systemd.services)
                && pi.systemd.timers.change-detection.timerConfig.OnCalendar == "*-*-* 00/6:13:00"
                && pi.systemd.timers.change-detection.timerConfig.RandomizedDelaySec == "5min";
              mediaSpecializationMatch =
                mediaDefinitionsMatch
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
                    {
                      protocol = "tcp";
                      hostPort = 18080;
                      containerPort = 8080;
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
                && alpha.systemd.services."container@jellyfin".serviceConfig.Nice == 10;
              validationMatches =
                builtins.all (result: !result.success) invalidDefinitions && !duplicateHostnames.success;
              hasAccessPolicy =
                rules: host: policy:
                builtins.any (rule: builtins.elem host rule.domain && rule.policy == policy) rules;
              ingressPolicyMatches =
                let
                  shareRule = builtins.elemAt accessControl.rules 0;
                  apiRule = builtins.elemAt accessControl.rules 1;
                  homeBypassRules = builtins.filter (
                    rule: rule.domain == [ "home.${cfg.domain}" ] && rule.policy == "bypass"
                  ) accessControl.rules;
                  # Every service exposing a healthcheck path and sitting behind authelia
                  # must be reachable unauthenticated (public-edge monitoring).
                  # Bypassed vhosts (jellyfin) don't need a healthcheck rule.
                  hasHealthcheckBypass =
                    name:
                    let
                      service = cfg.definitions.${name};
                    in
                    service.healthcheck == null
                    || service.auth == "bypass"
                    || service.hostname == null
                    || builtins.any (
                      rule:
                      rule.domain == [ "${service.hostname}.${cfg.domain}" ]
                      && rule.policy == "bypass"
                      && builtins.elem "^${lib.escapeRegex service.healthcheck}([?].*)?$" (rule.resources or [ ])
                    ) accessControl.rules;
                in
                !(matrixPolicy.traefik.routers.bypass ? middlewares)
                && matrixPolicy.traefik.routers.one.middlewares == [ "authelia" ]
                && matrixPolicy.traefik.routers.two.middlewares == [ "authelia" ]
                && hasAccessPolicy matrixPolicy.authelia.rules "bypass.example.test" "bypass"
                && hasAccessPolicy matrixPolicy.authelia.rules "one.example.test" "one_factor"
                && hasAccessPolicy matrixPolicy.authelia.rules "two.example.test" "two_factor"
                && !unsupportedExternal.success
                && !(builtins.any (rule: builtins.elem "null.example.test" rule.domain) sparsePolicy.authelia.rules)
                && !(http.routers ? opencode)
                && !(http.routers ? home-router)
                &&
                  http.routers.glance == {
                    rule = "Host(`${cfg.domain}`)";
                    service = "glance";
                  }
                &&
                  http.routers.homeassistant == {
                    rule = "Host(`home.${cfg.domain}`)";
                    service = "homeassistant";
                  }
                &&
                  http.routers.jellyfin == {
                    rule = "Host(`jellyfin.${cfg.domain}`)";
                    service = "jellyfin";
                  }
                &&
                  http.routers.authelia == {
                    rule = "Host(`auth.${cfg.domain}`)";
                    service = "authelia";
                  }
                && lib.all (name: http.routers.${name}.middlewares == [ "authelia" ]) [
                  "bazarr"
                  "finance"
                  "miniflux"
                  "paperless"
                  "prowlarr"
                  "radarr"
                  "sonarr"
                ]
                && http.routers.qbittorrent.rule == "Host(`qbit.${cfg.domain}`) && !PathPrefix(`/api`)"
                && http.routers.qbittorrent.middlewares == [ "qbit-auth" ]
                && http.routers.qbittorrent-api.rule == "Host(`qbit.${cfg.domain}`) && PathPrefix(`/api`)"
                &&
                  http.middlewares.qbit-auth.chain.middlewares == [
                    "authelia"
                    "qbit-basic-auth"
                  ]
                &&
                  http.middlewares.authelia.forwardAuth.address
                  == "http://${epsilon.containers.authelia.localAddress}:9091/api/authz/forward-auth"
                &&
                  http.services.authelia.loadBalancer.servers
                  == [ { url = "http://${epsilon.containers.authelia.localAddress}:9091"; } ]
                && http.services.homeassistant.loadBalancer.servers == [ { url = "http://192.168.0.4:8123"; } ]
                &&
                  http.services.glance.loadBalancer.servers
                  == [ { url = "http://${epsilon.containers.glance.localAddress}:8080"; } ]
                && http.services.jellyfin.loadBalancer.servers == [ { url = "http://192.168.0.18:8096"; } ]
                && http.services.qbittorrent.loadBalancer.servers == [ { url = "http://192.168.0.18:18080"; } ]
                && http.services.bazarr.loadBalancer.servers == [ { url = "http://192.168.0.18:6767"; } ]
                && http.services.finance.loadBalancer.servers == [ { url = "http://192.168.0.18:3000"; } ]
                &&
                  http.services.miniflux.loadBalancer.servers
                  == [ { url = "http://${epsilon.containers.miniflux.localAddress}:8081"; } ]
                && http.services.paperless.loadBalancer.servers == [ { url = "http://192.168.0.18:8000"; } ]
                && http.services.prowlarr.loadBalancer.servers == [ { url = "http://192.168.0.18:9696"; } ]
                && http.services.radarr.loadBalancer.servers == [ { url = "http://192.168.0.18:7878"; } ]
                && http.services.sonarr.loadBalancer.servers == [ { url = "http://192.168.0.18:8989"; } ]
                && shareRule.domain == [ "paper.${cfg.domain}" ]
                && shareRule.resources == [ "^/share/.*$" ]
                && shareRule.policy == "bypass"
                && builtins.elem "qbit.${cfg.domain}" apiRule.domain
                &&
                  apiRule.resources == [
                    "^/api([/?].*)?$"
                    "^/v1([/?].*)?$"
                  ]
                && apiRule.policy == "bypass"
                && builtins.length homeBypassRules == 1
                && hasAccessPolicy accessControl.rules "jellyfin.${cfg.domain}" "bypass"
                && hasAccessPolicy accessControl.rules "rss.${cfg.domain}" "one_factor"
                && lib.all hasHealthcheckBypass (lib.attrNames cfg.definitions)
                && (lib.last accessControl.rules).domain == [ "*.${cfg.domain}" ]
                && (lib.last accessControl.rules).subject == [ "group:admins" ]
                && accessControl.default_policy == "deny";
              publishedBackendMatch =
                !alpha.services.traefik.enable
                && !(builtins.elem 80 alpha.networking.firewall.interfaces.eth0.allowedTCPPorts)
                && !(builtins.elem 443 alpha.networking.firewall.interfaces.eth0.allowedTCPPorts)
                && builtins.elem 54535 alpha.networking.firewall.interfaces.eth0.allowedTCPPorts
                && builtins.any (lib.strings.hasInfix "ip saddr { 192.168.0.4, 10.5.5.3 } tcp dport { 3000, 8081 } accept") (
                  lib.splitString "\n" alpha.networking.firewall.extraInputRules
                )
                && lib.strings.hasInfix "ip saddr { 192.168.0.4, 10.5.5.3 } oifname \"ve-*\" accept" alpha.networking.firewall.extraForwardRules
                && builtins.all (port: builtins.elem port pi.networking.firewall.interfaces.eth0.allowedTCPPorts) [
                  80
                  443
                ]
                &&
                  alpha.containers.paperless.forwardPorts == [
                    {
                      protocol = "tcp";
                      hostPort = 8000;
                      containerPort = 8000;
                    }
                  ]
                &&
                  alpha.containers.jellyfin.forwardPorts == [
                    {
                      protocol = "tcp";
                      hostPort = 8096;
                      containerPort = 8096;
                    }
                  ]
                &&
                  alpha.containers.bazarr.forwardPorts == [
                    {
                      protocol = "tcp";
                      hostPort = 6767;
                      containerPort = 6767;
                    }
                  ]
                &&
                  alpha.containers.prowlarr.forwardPorts == [
                    {
                      protocol = "tcp";
                      hostPort = 9696;
                      containerPort = 9696;
                    }
                  ]
                &&
                  alpha.containers.radarr.forwardPorts == [
                    {
                      protocol = "tcp";
                      hostPort = 7878;
                      containerPort = 7878;
                    }
                  ]
                &&
                  alpha.containers.sonarr.forwardPorts == [
                    {
                      protocol = "tcp";
                      hostPort = 8989;
                      containerPort = 8989;
                    }
                  ];
              fleetUpdaterMatch =
                let
                  authorizedKeys = import ../authorized-keys.nix;
                in
                !alpha.systemd.services.alpha-auto-update.restartIfChanged
                && !pi.systemd.services.auto-update.restartIfChanged
                && lib.strings.hasInfix "--host alpha --state /var/lib/alpha-auto-update" alpha.systemd.services.alpha-auto-update.script
                && lib.strings.hasInfix "--update-lock --state /var/lib/auto-update" pi.systemd.services.auto-update.script
                && builtins.elem alpha.modules.fleet-update.package alpha.environment.systemPackages
                && builtins.elem pi.modules.fleet-update.package pi.environment.systemPackages
                && builtins.elem epsilon.modules.fleet-update.package epsilon.environment.systemPackages
                && lib.all (host: builtins.elem "d /run/deploy-rs 0700 root root -" host.systemd.tmpfiles.rules) [
                  alpha
                  pi
                  epsilon
                ]
                && lib.all (
                  key: builtins.elem key alpha.users.users.root.openssh.authorizedKeys.keys
                ) authorizedKeys
                && lib.all (key: builtins.elem key pi.users.users.root.openssh.authorizedKeys.keys) authorizedKeys
                && lib.all (
                  key: builtins.elem key epsilon.users.users.root.openssh.authorizedKeys.keys
                ) authorizedKeys;
              expected = builtins.all (value: value) [
                nativeServicesMatch
                authenticationPresentationMatch
                backgroundServicesMatch
                mediaSpecializationMatch
                validationMatches
                ingressPolicyMatches
                publishedBackendMatch
                fleetUpdaterMatch
              ];
              # Interpolated into the derivation below so that evaluating it
              # forces every matcher: an assert alone can be skipped by lazy
              # attribute selection on the flake output.
              matcherReport = builtins.toJSON {
                i = ingressPolicyMatches;
                p = publishedBackendMatch;
                n = nativeServicesMatch;
                a = authenticationPresentationMatch;
                m = mediaSpecializationMatch;
                b = backgroundServicesMatch;
                f = fleetUpdaterMatch;
                v = validationMatches;
              };
            in
            assert expected || throw matcherReport;
            pkgs.runCommand "check-service-definitions" { } ''
              echo "service definitions: valid derivation and invalid combination verified" > $out
              echo "matchers: ${matcherReport}" >> $out
            '';
        }
        // lib.genAttrs hosts evalHost;
    };
}
