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
              mkStub =
                pkgs: name:
                let
                  p = pkgs.writeShellScriptBin name "exit 0";
                in
                p
                // {
                  override = _: p;
                  extend = _: p;
                };
              stubbed = inputs.self.nixosConfigurations.${host}.extendModules {
                modules = [
                  (
                    { lib, pkgs, ... }:
                    {
                      nixpkgs.overlays = [
                        (final: prev: {
                          repparw-neovim = mkStub pkgs "nvim";
                        })
                      ];
                    }
                  )
                ]
                ++ lib.optionals (host == "epsilon") [
                  (
                    { lib, pkgs, ... }:
                    {
                      containers.hermes.config.services.hermes-agent.package = lib.mkForce (mkStub pkgs "hermes-agent");
                    }
                  )
                ]
                ++ lib.optionals (host == "alpha") [
                  (
                    { lib, pkgs, ... }:
                    {
                      home-manager.users.repparw.programs.helium.package = lib.mkForce (mkStub pkgs "helium");
                    }
                  )
                ];
              };
              evaluatedDrvPath = builtins.unsafeDiscardStringContext stubbed.config.system.build.toplevel.drvPath;
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

          agent-docs =
            pkgs.runCommand "check-agent-docs"
              {
                nativeBuildInputs = [ (pkgs.python3.withPackages (ps: [ ps.pyyaml ])) ];
              }
              ''
                export PYTHONDONTWRITEBYTECODE=1
                python3 ${./scripts}/check-agent-docs.test.py ${inputs.self}
                touch $out
              '';

          service-definitions =
            let
              alpha = inputs.self.nixosConfigurations.alpha.config;
              epsilon = inputs.self.nixosConfigurations.epsilon.config;
              domain = alpha.modules.services.domain;
              definitions = alpha.modules.services.definitions // epsilon.modules.services.definitions;
              accessControl =
                epsilon.containers.authelia.config.services.authelia.instances.main.settings.access_control;

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

              hasAccessPolicy =
                rules: host: policy:
                builtins.any (rule: builtins.elem host rule.domain && rule.policy == policy) rules;

              healthcheckBypassMatches = lib.all (
                name:
                let
                  service = definitions.${name};
                in
                service.healthcheck == null
                || service.auth == "bypass"
                || service.hostname == null
                || builtins.any (
                  rule:
                  rule.domain == [ "${service.hostname}.${domain}" ]
                  && rule.policy == "bypass"
                  && builtins.elem "^${lib.escapeRegex service.healthcheck}([?].*)?$" (rule.resources or [ ])
                ) accessControl.rules
              ) (lib.attrNames definitions);

              validationMatches =
                builtins.all (result: !result.success) invalidDefinitions && !duplicateHostnames.success;

              ingressPolicyMatches =
                !(matrixPolicy.traefik.routers.bypass ? middlewares)
                && matrixPolicy.traefik.routers.one.middlewares == [ "authelia" ]
                && matrixPolicy.traefik.routers.two.middlewares == [ "authelia" ]
                && hasAccessPolicy matrixPolicy.authelia.rules "bypass.example.test" "bypass"
                && hasAccessPolicy matrixPolicy.authelia.rules "one.example.test" "one_factor"
                && hasAccessPolicy matrixPolicy.authelia.rules "two.example.test" "two_factor"
                && !unsupportedExternal.success
                && !(builtins.any (rule: builtins.elem "null.example.test" rule.domain) sparsePolicy.authelia.rules)
                && healthcheckBypassMatches;

              expected = validationMatches && ingressPolicyMatches;
              matcherReport = builtins.toJSON {
                v = validationMatches;
                i = ingressPolicyMatches;
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
