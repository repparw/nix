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
              # The real, unstubbed toplevel: evaluating its drvPath is pure and
              # measured at 20-35s per host, so CI sees evaluation breakage in
              # every subtree (nixvim, helium, hermes) instead of masking it
              # behind stubs. unsafeDiscardStringContext keeps the tiny check
              # derivation from depending on the whole closure.
              evaluatedDrvPath =
                builtins.unsafeDiscardStringContext
                  inputs.self.nixosConfigurations.${host}.config.system.build.toplevel.drvPath;
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
          hermes-package-triage =
            (import ./aspects/services/hermes-package/_package.nix { inherit pkgs; }).check;
          coredump-collector =
            pkgs.runCommand "check-coredump-collector" { nativeBuildInputs = [ pkgs.python3 ]; }
              ''
                cp -r ${./aspects/services/coredump-watch} source
                chmod -R u+w source
                python3 -m unittest discover -s source -v
                touch $out
              '';

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

          monitoring-vm = import ./_tests/monitoring-vm.nix { inherit inputs pkgs; };

          monitoring-fleet = import ./_tests/monitoring-fleet.nix { inherit inputs lib pkgs; };

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
                ${pkgs.shellcheck}/bin/shellcheck -s bash ${probe}
                node --test ${./_tests/fleet-failed-units.mjs}
                touch $out
              '';

          free-model-watch =
            pkgs.runCommand "check-free-model-watch"
              {
                LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
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
                  pkgs.git
                  pkgs.actionlint
                ];
              }
              ''
                cd ${inputs.self}
                node --test .github/scripts/ci.test.mjs .github/scripts/ci-impact.test.mjs
                actionlint -shellcheck= .github/workflows/ci.yml .github/workflows/revision-validation.yml .github/workflows/pr-title.yml .github/workflows/upstream-watch.yml
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

          # Alpha's home-state staging: exercises the production
          # prepare-home-state script against a fixture home — including the
          # critical-file guards for the OpenTofu state — and asserts the
          # evaluated alpha configuration keeps both backup destinations
          # covered.
          home-state-backup =
            let
              prepareHomeState = import ./_scripts/prepare-home-state.nix { inherit pkgs lib; };
              staging = prepareHomeState {
                home = "/tmp/home-state-fixture-home";
                stateRoot = "/tmp/home-state-fixture-root";
                paths = [
                  ".config/vesktop/settings.json"
                  ".local/share/fish/fish_history"
                  "Projects/nix/infra/terraform.tfstate"
                ];
                criticalPaths = [ "Projects/nix/infra/terraform.tfstate" ];
                hddOnlyPaths = [ ".config/sops/age/keys.txt" ];
              };
              # Cut the string context: these evaluated values are plain
              # paths and the check derivation must not depend on the host
              # closure (same trick as evalHost above).
              alpha = inputs.self.nixosConfigurations.alpha.config;
              alphaHomeState = map builtins.unsafeDiscardStringContext alpha.modules.backup.homeState;
              bupstateSources = map builtins.unsafeDiscardStringContext alpha.services.rsync.jobs.bupstate.sources;
              resticPaths = map builtins.unsafeDiscardStringContext alpha.services.restic.backups.offsite.paths;
            in
            pkgs.runCommand "check-home-state-backup"
              {
                nativeBuildInputs = [
                  pkgs.coreutils
                  pkgs.jq
                  pkgs.rsync
                ];
              }
              ''
                home=/tmp/home-state-fixture-home
                state_root=/tmp/home-state-fixture-root
                state_dir=$home/Projects/nix/infra
                state=$state_dir/terraform.tfstate

                rm -rf /tmp/home-state-fixture-*
                mkdir -p $home/.config/vesktop $home/.local/share/fish \
                  $home/.config/sops/age $state_dir/.terraform $state_root
                printf '{}' > $home/.config/vesktop/settings.json
                printf 'history\n' > $home/.local/share/fish/fish_history
                printf 'x' > $home/.config/sops/age/keys.txt
                # The never-backed-up neighbors of the state file; the state
                # itself is created later so the bootstrap scenario can run
                # without it.
                printf 'x' > $state_dir/.terraform/provider-cache
                printf 'x' > $state_dir/terraform.tfvars
                printf 'x' > $state_dir/terraform.tfplan

                # Evaluated alpha configuration coverage.
                home_state='${builtins.toJSON alphaHomeState}'
                printf '%s' "$home_state" | jq -e 'index("Projects/nix/infra/terraform.tfstate")' >/dev/null
                # Existing selection must stay untouched (spot check).
                for kept in .config/moonshine/ .config/net.imput.helium/ .local/share/shadPS4/keys.json Games/bbport/source/data/user/; do
                  printf '%s' "$home_state" | jq -e --arg kept "$kept" 'index($kept)' >/dev/null
                done
                sources='${builtins.toJSON bupstateSources}'
                printf '%s' "$sources" | jq -e 'index("/var/lib/home-state-backup/hdd/Projects")' >/dev/null
                restic_paths='${builtins.toJSON resticPaths}'
                printf '%s' "$restic_paths" | jq -e 'index("/var/lib/home-state-backup/offsite")' >/dev/null

                # Bootstrap: a missing critical source without a prior backup
                # marker is tolerated (host without tofu yet).
                ${staging} offsite
                staged=$state_root/offsite
                test ! -e $staged/Projects/nix/infra/terraform.tfstate
                test -f $staged/.config/vesktop/settings.json
                test ! -e $state_root/.critical-seen/Projects__nix__infra__terraform.tfstate

                # Evaluated alpha configuration coverage.
                home_state='${builtins.toJSON alphaHomeState}'
                printf '%s' "$home_state" | jq -e 'index("Projects/nix/infra/terraform.tfstate")' >/dev/null
                # Existing selection must stay untouched (spot check).
                for kept in .config/moonshine/ .config/net.imput.helium/ .local/share/shadPS4/keys.json Games/bbport/source/data/user/; do
                  printf '%s' "$home_state" | jq -e --arg kept "$kept" 'index($kept)' >/dev/null
                done
                sources='${builtins.toJSON bupstateSources}'
                printf '%s' "$sources" | jq -e 'index("/var/lib/home-state-backup/hdd/Projects")' >/dev/null
                restic_paths='${builtins.toJSON resticPaths}'
                printf '%s' "$restic_paths" | jq -e 'index("/var/lib/home-state-backup/offsite")' >/dev/null

                # Off-site staging: state plus the rest of the allowlist,
                # never the neighbors.
                printf '{"version": 4, "serial": 1, "resources": [{"type": "oci_core_instance", "name": "epsilon"}]}' > $state
                chmod 600 $state
                ${staging} offsite
                test -f $staged/Projects/nix/infra/terraform.tfstate
                test "$(stat -c %a $staged/Projects/nix/infra/terraform.tfstate)" = 600
                test -f $staged/.config/vesktop/settings.json
                test -f $staged/.local/share/fish/fish_history
                test -f $staged/.export-complete
                test -f $state_root/.critical-seen/Projects__nix__infra__terraform.tfstate
                test ! -e $staged/Projects/nix/infra/terraform.tfvars
                test ! -e $staged/Projects/nix/infra/terraform.tfplan
                test ! -e $staged/Projects/nix/infra/.terraform
                test ! -e $staged/.config/sops/age

                # A corrupt state fails the export and preserves the previous
                # valid staged generation.
                previous_stamp=$(cat $staged/.export-complete)
                printf 'not json {{' > $state
                if ${staging} offsite; then
                  echo 'corrupt state must fail the export' >&2
                  exit 1
                fi
                test "$(cat $staged/.export-complete)" = "$previous_stamp"
                jq -e . $staged/Projects/nix/infra/terraform.tfstate >/dev/null

                # After a successful backup, a missing critical source is an
                # alarm, not a silent gap.
                rm $state
                if ${staging} offsite; then
                  echo 'disappeared state must fail the export' >&2
                  exit 1
                fi
                test -f $staged/Projects/nix/infra/terraform.tfstate
                test "$(cat $staged/.export-complete)" = "$previous_stamp"

                # Never capture while OpenTofu holds the state lock.
                printf '{"version": 4, "serial": 2, "resources": []}' > $state
                touch $state_dir/.terraform.tfstate.lock.info
                if ${staging} offsite; then
                  echo 'locked state must fail the export' >&2
                  exit 1
                fi
                rm $state_dir/.terraform.tfstate.lock.info

                # HDD destination additionally stages the age keys and the
                # critical state.
                ${staging} hdd
                test -f $state_root/hdd/Projects/nix/infra/terraform.tfstate
                test -f $state_root/hdd/.config/sops/age/keys.txt

                touch $out
              '';

          # Static validation of the OCI root module in infra/: formatting
          # plus schema validation against the pinned provider, fetched from
          # the upstream release so the check needs no network or registry.
          tofu =
            let
              ociProvider = pkgs.fetchurl {
                # Keep in sync with infra/.terraform.lock.hcl (same zh hash).
                url = "https://github.com/oracle/terraform-provider-oci/releases/download/v6.37.0/terraform-provider-oci_6.37.0_linux_amd64.zip";
                sha256 = "3e3017f035fac18114e0b1d29c72430958054def0f800c22d36e1144d0c76422";
              };
            in
            pkgs.runCommand "check-tofu"
              {
                nativeBuildInputs = [
                  pkgs.opentofu
                  pkgs.unzip
                ];
              }
              ''
                export HOME=$TMPDIR
                export TF_IN_AUTOMATION=1

                # OpenTofu's -plugin-dir search path expects the provider
                # binary as a file at
                # <dir>/<host>/<namespace>/<type>/<version>/<os>_<arch>/.
                plugin_dir=$TMPDIR/plugins/registry.opentofu.org/oracle/oci/6.37.0/linux_amd64
                mkdir -p "$plugin_dir"
                unzip -q -j ${ociProvider} -d "$plugin_dir"

                cp -r ${inputs.self}/infra module
                chmod -R u+w module
                cd module
                mkdir -p .terraform
                tofu init -backend=false -input=false -plugin-dir="$TMPDIR/plugins"
                tofu fmt -check -recursive .
                tofu validate .
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
                python3 ${./scripts}/fleet-update.test.py ${./scripts/fleet-update.sh}
                python3 ${./scripts/fleet-readiness.test.py} ${./scripts/fleet-readiness-probe.sh} ${./scripts/fleet-readiness-deliver.sh}
                python3 ${./scripts/pi-generation-retention.test.py} ${./scripts/pi-generation-retention.py}
                python3 ${./scripts/package-update-event.test.py} ${./scripts/package-update-event.py}
                python3 ${./scripts/lock-update.test.py} ${inputs.self}/.github/workflows/lock-update.yml ${inputs.self}/.github/workflows/ci.yml ${inputs.self}/.github/workflows/revision-validation.yml
                touch $out
              '';

          bttoggle =
            pkgs.runCommand "check-bttoggle"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.python3
                  pkgs.shellcheck
                ];
              }
              ''
                shellcheck --shell=bash ${./scripts/bttoggle.sh}
                python3 ${./scripts/bttoggle.test.py} ${./scripts/bttoggle.sh}
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

              glanceServices = import ./_services/lib.nix { inherit lib pkgs; };
              glanceSites = glanceServices.monitorSites epsilon.modules.services epsilon;
              protectedLanSite = builtins.head (
                glanceServices.monitorSites (
                  epsilon.modules.services
                  // {
                    definitions.paperless = epsilon.modules.services.definitions.paperless // {
                      lanEdge = true;
                    };
                  }
                ) epsilon
              );
              glanceCheckUrl =
                name: (lib.findFirst (site: site.title == name) { } glanceSites)."check-url" or null;
              glanceHosts = epsilon.containers.glance.config.networking.hosts;
              glanceRoutingMatches =
                glanceCheckUrl "homeassistant" == "https://home.${domain}"
                && lib.hasPrefix "http://" (glanceCheckUrl "paperless")
                && protectedLanSite."check-url" == glanceCheckUrl "paperless"
                && glanceCheckUrl "jellyfin" == "https://jellyfin.${domain}/health"
                && builtins.elem "home.${domain}" (glanceHosts."${epsilon.modules.services.bridgePrefix}.1" or [ ])
                && builtins.elem "jellyfin.${domain}" (
                  glanceHosts.${epsilon.modules.services.hostAddresses.pi} or [ ]
                )
                && builtins.elem "rss.${domain}" (glanceHosts."${epsilon.modules.services.bridgePrefix}.1" or [ ]);

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

              edgeTunnel = epsilon.services.cloudflared.tunnels.epsilon-edge;
              tunnelRoutingMatches =
                builtins.hasAttr domain edgeTunnel.ingress
                && !(builtins.hasAttr "jellyfin.${domain}" edgeTunnel.ingress)
                && builtins.hasAttr "qbit.${domain}" edgeTunnel.ingress
                &&
                  epsilon.services.traefik.dynamicConfigOptions.http.routers.qbittorrent.middlewares
                  == [ "qbit-auth" ]
                && lib.all (
                  host:
                  edgeTunnel.ingress.${host}.service == "https://127.0.0.1:8443"
                  && edgeTunnel.ingress.${host}.originRequest.originServerName == host
                  && edgeTunnel.ingress.${host}.originRequest.noTLSVerify != true
                ) (lib.attrNames edgeTunnel.ingress)
                && edgeTunnel.default == "http_status:404"
                && epsilon.services.traefik.staticConfigOptions.entryPoints.tunnel.address == "127.0.0.1:8443"
                && !epsilon.services.ddclient.enable;

              hardeningMatches =
                builtins.hasAttr "metrics.${domain}" edgeTunnel.ingress
                && epsilon.services.traefik.staticConfigOptions.api.dashboard == false
                && epsilon.services.traefik.staticConfigOptions.api.debug == false
                && epsilon.containers.paperless.forwardPorts == [ ];

              expected =
                fleetRegistryMatches
                && validationMatches
                && ingressPolicyMatches
                && glanceRoutingMatches
                && tunnelRoutingMatches
                && hardeningMatches;
              matcherReport = builtins.toJSON {
                r = fleetRegistryMatches;
                v = validationMatches;
                i = ingressPolicyMatches;
                g = glanceRoutingMatches;
                t = tunnelRoutingMatches;
                h = hardeningMatches;
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
