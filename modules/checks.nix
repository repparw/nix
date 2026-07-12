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
              expected =
                miniflux.hostname == "rss"
                && miniflux.port == 8081
                && miniflux.auth == "one_factor"
                && miniflux.monitor
                && miniflux.backup.path == "${cfg.configDir}/miniflux"
                && http.routers.miniflux.rule == "Host(`rss.${cfg.domain}`)"
                && http.routers.miniflux.middlewares == [ "authelia" ]
                && http.services.miniflux.loadBalancer.servers == [ { url = "http://127.0.0.1:8081"; } ]
                && builtins.any (
                  widget:
                  widget.type or null == "monitor"
                  && builtins.any (
                    site:
                    site.title == "miniflux"
                    && site.url == "https://rss.${cfg.domain}"
                    && site.check-url == "http://127.0.0.1:8081"
                  ) widget.sites
                ) (lib.concatMap (column: column.widgets) monitorSites.columns)
                && alpha.fileSystems."${cfg.backupDir}/miniflux".device == "${cfg.configDir}/miniflux"
                && builtins.elem "home-containers-backup-miniflux.mount" alpha.systemd.services.miniflux.after
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
