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
                && builtins.all (result: !result.success) invalidDefinitions;
            in
            assert expected;
            pkgs.runCommand "check-service-definitions" { } ''
              echo "service definitions: valid derivation and invalid combination verified" > $out
            '';
        }
        // lib.genAttrs hosts evalHost;
    };
}
