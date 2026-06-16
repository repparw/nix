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
                  inventory = lib.attrValues (
                    inputs.self.nixosConfigurations.${host}.config.modules.services.inventory or { }
                  );
                  ips = lib.filter (x: x != null) (lib.catAttrs "containerAddress" inventory);
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
        }
        // lib.genAttrs hosts evalHost;
    };
}
