{ inputs, lib, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      checks =
        let
          hosts = lib.attrNames inputs.self.nixosConfigurations;
          fleetCli = inputs.self.nixosConfigurations.alpha.config.modules.fleet-cli.package;
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
          hermes-crash-triage = (import ./aspects/services/hermes-crash/_package.nix { inherit pkgs; }).check;

          coredump-collector =
            pkgs.runCommand "check-coredump-collector" { nativeBuildInputs = [ pkgs.python3 ]; }
              ''
                cp -r ${./aspects/services/coredump-watch} source
                chmod -R u+w source
                python3 -m unittest discover -s source -v
                touch $out
              '';

          hermes-auxiliary-routing =
            (pkgs.callPackage ./_packages/hermes-agent.nix {
              upstream = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.messaging;
            }).tests.auxiliary-routing;

          btrfs-health =
            let
              script = pkgs.writeText "btrfs-health-root.sh" inputs.self.nixosConfigurations.alpha.config.systemd.services.btrfs-health-root.script;
            in
            pkgs.runCommand "check-btrfs-health"
              {
                nativeBuildInputs = with pkgs; [
                  nodejs
                  bash
                  coreutils
                  gawk
                  gnugrep
                  shellcheck
                ];
              }
              ''
                shellcheck --shell=bash ${script}
                node ${./_tests/btrfs-health.mjs} ${script}
                touch $out
              '';

          host-persistence = import ./_tests/host-persistence.nix { inherit inputs lib pkgs; };
          host-persistence-vm = import ./_tests/host-persistence-vm.nix { inherit inputs pkgs; };

          fleet-failed-units =
            let
              expectedJobs = {
                alpha = [
                  "restic-backups-offsite"
                  "btrfs-health-root"
                  "btrfs-scrub@"
                  "jellyfin-backup"
                  "rsync-job-buprpi"
                ];
                pi = [ "restic-backups-offsite" ];
                epsilon = [ "restic-backups-offsite" ];
              };
              retainedJobsHaveHooks = lib.all (
                host:
                lib.all (
                  job:
                  lib.hasInfix "/fleet-unit-record %n"
                    inputs.self.nixosConfigurations.${host}.config.systemd.units."${job}.service".text
                ) expectedJobs.${host}
              ) (lib.attrNames expectedJobs);
              collectorsAreInstalled = lib.all (
                host:
                let
                  config = inputs.self.nixosConfigurations.${host}.config;
                in
                lib.elem config.modules.fleet-unit-state.snapshot config.environment.systemPackages
              ) (lib.attrNames expectedJobs);
              probe = pkgs.writeText "fleet-health-probe-test.sh" (
                builtins.unsafeDiscardStringContext inputs.self.nixosConfigurations.pi.config.modules.fleet-health.probe.text
              );
            in
            assert retainedJobsHaveHooks;
            assert collectorsAreInstalled;
            pkgs.runCommand "check-fleet-failed-units"
              {
                nativeBuildInputs = with pkgs; [
                  nodejs
                  bash
                  coreutils
                  findutils
                  gawk
                  gnugrep
                  util-linux
                ];
                FLEET_HEALTH_PROBE = probe;
                FLEET_UNIT_SOURCE = ./aspects/fleet-unit-state;
                TEST_BASH = "${pkgs.bash}/bin/bash";
              }
              ''
                node --test ${./_tests/fleet-failed-units.mjs}
                touch $out
              '';

          free-model-watch =
            pkgs.runCommand "check-free-model-watch"
              {
                nativeBuildInputs = with pkgs; [
                  python3
                  bash
                  coreutils
                  jq
                  gnused
                  gnugrep
                ];
              }
              ''
                python ${./_tests/free-model-watch.py} ${inputs.self.nixosConfigurations.alpha.config.modules.free-model-watch.script}/bin/free-model-watch
                touch $out
              '';

          ci-workflow =
            pkgs.runCommand "check-ci-workflow"
              {
                nativeBuildInputs = [
                  pkgs.nodejs
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.actionlint
                ];
              }
              ''
                cd ${inputs.self}
                node --test .github/scripts/ci.test.mjs
                actionlint -shellcheck= .github/workflows/ci.yml
                touch $out
              '';

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

          generated-shellcheck =
            pkgs.runCommand "check-generated-shellcheck"
              {
                nativeBuildInputs = [ pkgs.shellcheck ];
              }
              ''
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

          fleet-cli =
            pkgs.runCommand "check-fleet-cli"
              {
                nativeBuildInputs = [
                  fleetCli
                  pkgs.jq
                  pkgs.python3
                  pkgs.bash
                  pkgs.git
                  pkgs.util-linux
                ];
              }
              ''
                fleet --help >/dev/null
                fleet health --help >/dev/null
                fleet backup --help >/dev/null

                registry=$(fleet commands --json)
                printf '%s\n' "$registry" | jq -e 'type == "array" and length > 0' >/dev/null

                while IFS= read -r row; do
                  usage=$(printf '%s' "$row" | jq -r .usage)
                  mapfile -t path < <(printf '%s' "$row" | jq -r '.path[]')
                  help=$(fleet "''${path[@]}" --help)
                  grep -F "Usage: $usage" <<< "$help" >/dev/null
                done < <(printf '%s\n' "$registry" | jq -c '.[]')

                if fleet commands nope >/dev/null 2>&1; then
                  echo "fleet commands accepted an invalid argument" >&2
                  exit 1
                fi
                if fleet backup status nope >/dev/null 2>&1; then
                  echo "fleet backup status accepted an invalid argument" >&2
                  exit 1
                fi
                if fleet debug not-a-host >/dev/null 2>&1; then
                  echo "fleet debug accepted an unknown host" >&2
                  exit 1
                fi

                python3 ${./scripts/fleet-update-notifications.test.py} ${./scripts/fleet-update.sh}
                python3 ${./scripts/fleet-update.test.py} ${./scripts/fleet-update.sh}
                python3 ${./scripts/pi-generation-retention.test.py} ${./scripts/pi-generation-retention.py}
                python3 ${./scripts/lock-update.test.py} ${inputs.self}/.github/workflows/lock-update.yml ${inputs.self}/.github/workflows/ci.yml ${inputs.self}/.github/workflows/revision-validation.yml
                touch $out
              '';

          service-definitions =
            let
              alpha = inputs.self.nixosConfigurations.alpha.config;
              pi = inputs.self.nixosConfigurations.pi.config;
              epsilon = inputs.self.nixosConfigurations.epsilon.config;
              domain = alpha.modules.services.domain;
              definitions = alpha.modules.services.definitions // epsilon.modules.services.definitions;
              registryNames = config: lib.attrNames config.modules.services.definitions;
              fleetRegistryMatches =
                registryNames alpha == registryNames pi && registryNames alpha == registryNames epsilon;
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

              expected = fleetRegistryMatches && validationMatches && ingressPolicyMatches;
              matcherReport = builtins.toJSON {
                r = fleetRegistryMatches;
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
