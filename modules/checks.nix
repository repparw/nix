{
  inputs,
  lib,
  den,
  ...
}:
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
          grafana-alert-triage =
            (import ./aspects/services/hermes-alert/_package.nix { inherit pkgs; }).check;
          coredump-collector =
            pkgs.runCommand "check-coredump-collector" { nativeBuildInputs = [ pkgs.python3 ]; }
              ''
                cp -r ${./aspects/services/coredump-watch} source
                chmod -R u+w source
                python3 -m unittest discover -s source -v
                touch $out
              '';

          antigravity-cli-runtime = import ./_tests/antigravity-cli-runtime.nix { inherit pkgs; };

          t3code-providers =
            let
              expectedProviders = [
                "antigravity"
                "antigravity_2"
                "codex"
                "codex_2"
                "opencode"
              ];
              records = map (
                host:
                let
                  instances =
                    inputs.self.nixosConfigurations.${host}.config.home-manager.users.repparw.programs.t3code.userSettings.providerInstances;
                in
                {
                  inherit host;
                  providers = lib.attrNames instances;
                  antigravityBinary = builtins.unsafeDiscardStringContext instances.antigravity.config.binaryPath;
                  antigravity2Binary = builtins.unsafeDiscardStringContext instances.antigravity_2.config.binaryPath;
                }
              ) (lib.attrNames inputs.self.nixosConfigurations);
            in
            assert lib.all (
              record:
              record.providers == expectedProviders
              && record.antigravityBinary == record.antigravity2Binary
              && lib.hasSuffix "-antigravity-cli-runtime-1.5.9/bin/agy" record.antigravityBinary
            ) records;
            pkgs.writeText "t3code-providers.json" (builtins.toJSON records);

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

          host-nat =
            let
              pi = inputs.self.nixosConfigurations.pi.config;
              masquerade = pi.networking.nftables.tables.container-nat.content;
            in
            assert !(lib.elem "ve-+" pi.networking.nat.internalInterfaces);
            assert lib.hasInfix "${pi.modules.services.bridgePrefix}.0/24 oifname \"eth0\" masquerade"
              masquerade;
            pkgs.writeText "host-nat-evaluation.json" (
              builtins.toJSON {
                inherit (pi.networking.nat) internalInterfaces;
                containerNat = masquerade;
              }
            );

          # Every host must see the same topology, including machines that
          # publish no services and LAN addresses only where configured.
          service-host-inventory =
            let
              hosts = lib.concatMapAttrs (_system: machines: machines) den.hosts;
              hostNames = lib.attrNames inputs.self.nixosConfigurations;
              expectedAddresses = lib.mapAttrs (_: host: host.serviceAddress) hosts;
              expectedLanAddresses = lib.mapAttrs (_: host: host.lanAddress) (
                lib.filterAttrs (_: host: host ? lanAddress) hosts
              );
              inventories = map (name: inputs.self.nixosConfigurations.${name}.config.modules.services) hostNames;
            in
            assert lib.attrNames hosts == hostNames;
            assert lib.all (
              inventory:
              inventory.hostAddresses == expectedAddresses && inventory.hostLanAddresses == expectedLanAddresses
            ) inventories;
            pkgs.writeText "service-host-inventory.json" (
              builtins.toJSON {
                inherit expectedAddresses expectedLanAddresses;
              }
            );

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
                  pkgs.jq
                  pkgs.gnugrep
                ];
              }
              ''
                cd ${inputs.self}
                node --test .github/scripts/ci.test.mjs .github/scripts/ci-impact.test.mjs .github/scripts/main-packages.test.mjs
                actionlint -shellcheck= .github/workflows/*.yml
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
                treefmt --tree-root . --walk filesystem --fail-on-change || {
                  ${pkgs.diffutils}/bin/diff -ru ${inputs.self} . | head -n 300 || true
                  exit 1
                }
                touch $out
              '';

          cachix-push = import ./_tests/cachix-push.nix { inherit pkgs; };

          generated-shellcheck =
            pkgs.runCommand "check-generated-shellcheck"
              {
                nativeBuildInputs = [ pkgs.shellcheck ];
              }
              ''
                ${generatedShellChecks}
                touch $out
              '';

          home-state-backup =
            let
              prepareHomeState = import ./_scripts/prepare-home-state.nix { inherit pkgs lib; };
              fakeRestic = pkgs.writeShellScriptBin "restic" ''
                for arg in "$@"; do
                  if [ "$arg" = backup ]; then
                    touch "$RESTIC_FAKE_STARTED"
                    while [ ! -e "$RESTIC_FAKE_RELEASE" ]; do
                      ${pkgs.coreutils}/bin/sleep 0.1
                    done
                    break
                  fi
                done
              '';
              lockedRestic = import ./_scripts/stage-locked-restic.nix { inherit pkgs lib; } {
                lockFile = "/tmp/home-state-fixture-root/.stage.lock";
                restic = fakeRestic;
              };
              staging = prepareHomeState {
                home = "/tmp/home-state-fixture-home";
                stateRoot = "/tmp/home-state-fixture-root";
                persistentStateDir = "/tmp/home-state-fixture-persistent";
                paths = [
                  ".config/vesktop/settings.json"
                  ".config/net.imput.helium/Default/Bookmarks"
                  ".local/share/opencode/"
                  "Projects/nix/infra/terraform.tfstate"
                ];
                excludes = [
                  "/.local/share/opencode/log/"
                  "/.local/share/opencode/tool-output/"
                ];
                criticalPaths = [ "Projects/nix/infra/terraform.tfstate" ];
              };
              # Inspect the evaluated production selection without depending
              # on the entire Alpha host closure.
              alpha = inputs.self.nixosConfigurations.alpha.config;
              alphaHomeState = map builtins.unsafeDiscardStringContext alpha.modules.backup.homeState;
              rsyncJobs = builtins.attrNames alpha.services.rsync.jobs;
              resticPaths = map builtins.unsafeDiscardStringContext alpha.services.restic.backups.offsite.paths;
              offsiteArgs = map builtins.unsafeDiscardStringContext alpha.services.restic.backups.offsite.extraBackupArgs;
              claroArgs = map builtins.unsafeDiscardStringContext alpha.services.restic.backups.claro.extraBackupArgs;
            in
            pkgs.runCommand "check-home-state-backup"
              {
                nativeBuildInputs = [
                  pkgs.coreutils
                  pkgs.jq
                  pkgs.util-linux
                  pkgs.python3
                  pkgs.sqlite
                ];
              }
              ''
                                home=/tmp/home-state-fixture-home
                                state_root=/tmp/home-state-fixture-root
                                rm -rf /tmp/home-state-fixture-*
                                mkdir -p "$home/.config/vesktop" \
                                  "$home/.config/net.imput.helium/Default" \
                                  "$home/.local/share/opencode/log" \
                                  "$home/Projects/nix/infra" "$state_root"
                                printf '{}' > "$home/.config/vesktop/settings.json"
                                printf '{"roots":{}}\n' > "$home/.config/net.imput.helium/Default/Bookmarks"
                                printf '{"version":4,"serial":1,"resources":[]}\n' > "$home/Projects/nix/infra/terraform.tfstate"
                                printf 'log' > "$home/.local/share/opencode/log/current.log"
                                printf 'secret' > "$home/.local/share/opencode/auth.json"
                                sqlite3 "$home/.local/share/opencode/opencode.db" \
                                  "CREATE TABLE session(value TEXT); INSERT INTO session VALUES('saved');"
                                sqlite3 "$home/.config/net.imput.helium/Default/DIPS" 'CREATE TABLE test(x)'

                                home_state='${builtins.toJSON alphaHomeState}'
                                printf '%s' "$home_state" | jq -e '
                                  index(".config/net.imput.helium/") == null and
                                  index(".config/net.imput.helium/Default/Bookmarks") != null and
                                  index(".config/net.imput.helium/Default/Preferences") != null and
                                  index(".config/net.imput.helium/Default/Sessions/") != null and
                                  index(".config/net.imput.helium/Local State") != null and
                                  index("Projects/nix/infra/terraform.tfstate") != null
                                ' >/dev/null
                                jobs='${builtins.toJSON rsyncJobs}'
                                printf '%s' "$jobs" | jq -e '(index("bupstate") == null) and (index("buptohdd") == null)' >/dev/null
                                paths='${builtins.toJSON resticPaths}'
                                printf '%s' "$paths" | jq -e 'index("/run/home-state-backup/offsite")' >/dev/null
                                for args in '${builtins.toJSON offsiteArgs}' '${builtins.toJSON claroArgs}'; do
                                  printf '%s' "$args" | jq -e \
                                    'index("--files-from-raw=/run/home-state-backup/offsite/.home-files") != null and index("--exclude-file=/run/home-state-backup/offsite/.home-excludes") != null' >/dev/null
                                done

                                ${staging}
                                staged="$state_root/offsite"
                                test -f "$staged/.export-complete"
                                jq -e '.status == "complete"' "$staged/.export-status.json" >/dev/null
                                test ! -e "$staged/.config/vesktop/settings.json"
                                test ! -e "$staged/Projects/nix/infra/terraform.tfstate"
                                test ! -e "$staged/.config/net.imput.helium/Default/Bookmarks"
                                test ! -e "$staged/.config/net.imput.helium/Default/DIPS"
                                test ! -e "$staged/.local/share/opencode/log"
                                test "$(sqlite3 "$staged/.local/share/opencode/opencode.db" \
                                  'SELECT value FROM session')" = saved

                                python3 - "$home" "$staged/.home-files" "$staged/.home-excludes" <<'PY'
                import os
                from pathlib import Path
                import sys
                home = Path(sys.argv[1])
                paths = set(Path(os.fsdecode(part)) for part in
                            Path(sys.argv[2]).read_bytes().split(b"\0") if part)
                expected = {
                    home / ".config/vesktop/settings.json",
                    home / ".config/net.imput.helium/Default/Bookmarks",
                    home / "Projects/nix/infra/terraform.tfstate",
                    home / ".local/share/opencode",
                }
                assert paths == expected, (paths, expected)
                excludes = set(Path(sys.argv[3]).read_text().splitlines())
                for required in (
                    str(home / ".local/share/opencode/log"),
                    str(home / ".local/share/opencode/tool-output"),
                    str(home / ".local/share/opencode/opencode.db"),
                    str(home / ".local/share/opencode/opencode.db-wal"),
                ):
                    assert required in excludes, (required, excludes)
                PY

                                export RESTIC_FAKE_STARTED="$state_root/restic-started"
                                export RESTIC_FAKE_RELEASE="$state_root/restic-release"
                                ${lib.getExe lockedRestic} -o rclone.connections=2 backup fixture &
                                restic_pid=$!
                                for attempt in $(seq 1 100); do
                                  test -f "$RESTIC_FAKE_STARTED" && break
                                  sleep 0.1
                                done
                                test -f "$RESTIC_FAKE_STARTED"
                                if flock -x -n "$state_root/.stage.lock" true; then
                                  echo 'Restic did not retain the SQLite export lock' >&2
                                  exit 1
                                fi
                                touch "$RESTIC_FAKE_RELEASE"
                                wait "$restic_pid"
                                flock -x -n "$state_root/.stage.lock" true

                                PYTHONDONTWRITEBYTECODE=1 python3 ${./_tests/home-state-sqlite.test.py} ${./scripts/home-state-sqlite.py}
                                touch $out
              '';

          tofu =
            let
              ociVersion =
                let
                  lockFile = builtins.readFile ../infra/.terraform.lock.hcl;
                  marker = "provider \"registry.opentofu.org/oracle/oci\" {";
                  parts = lib.splitString marker lockFile;
                  block = builtins.head (lib.splitString "}" (lib.last parts));
                  versions = builtins.filter (v: v != null) (
                    map (builtins.match "[[:space:]]*version[[:space:]]*=[[:space:]]*\"([^\"]+)\"[[:space:]]*") (
                      lib.splitString "\n" block
                    )
                  );
                in
                if parts == [ lockFile ] then
                  throw "checks.tofu: infra/.terraform.lock.hcl has no registry.opentofu.org/oracle/oci provider block"
                else if versions == [ ] then
                  throw "checks.tofu: the oracle/oci provider block in infra/.terraform.lock.hcl has no version"
                else
                  builtins.head (builtins.head versions);
              ociProvider = pkgs.fetchurl {
                url = "https://github.com/oracle/terraform-provider-oci/releases/download/v${ociVersion}/terraform-provider-oci_${ociVersion}_linux_amd64.zip";
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
                plugin_dir=$TMPDIR/plugins/registry.opentofu.org/oracle/oci/${ociVersion}/linux_amd64
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
                nativeBuildInputs = [
                  (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
                  pkgs.git
                  config.pre-commit.settings.package
                ];
              }
              ''
                export PYTHONDONTWRITEBYTECODE=1
                python3 ${./scripts}/check-agent-docs.test.py ${inputs.self}

                # Verify the generated hooks, not just their Nix declarations.
                hook_config=${config.pre-commit.settings.configFile}
                python3 - "$hook_config" <<'PY'
                import json
                import re
                import sys
                from pathlib import Path

                lines = Path(sys.argv[1]).read_text().splitlines()
                config = json.loads("\n".join(line for line in lines if not line.startswith("#")))
                hooks = [hook for repo in config["repos"] for hook in repo["hooks"]]
                by_id = {hook["id"]: hook for hook in hooks}

                assert len(by_id) == len(hooks), "duplicate hook ID"
                assert "format" in by_id and "shellcheck" in by_id and "agent-docs" in by_id, "missing hook"
                assert re.search(by_id["format"]["files"], "README.md")
                assert re.search(by_id["format"]["files"], "modules/checks.nix")
                assert not re.search(by_id["format"]["files"], "decisions.tsv")
                assert by_id["agent-docs"]["pass_filenames"] is False
                assert re.search(by_id["agent-docs"]["files"], ".agents/skills/probe/SKILL.md")
                assert not re.search(by_id["agent-docs"]["files"], "README.md")
                PY

                # Smoke-test generated hooks against disposable, staged fixture files.
                mkdir -p hook-fixture/.agents/skills/probe
                cd hook-fixture
                git init -q
                printf '%s\n' '---' 'name: probe' 'description: Example skill.' '---' > .agents/skills/probe/SKILL.md
                printf '%s\n' '# Example' > README.md
                git add .
                export PREK_HOME="$TMPDIR/prek-home"
                runner=${pkgs.lib.getExe config.pre-commit.settings.package}
                "$runner" run agent-docs --config "$hook_config" --files .agents/skills/probe/SKILL.md

                printf '%s\n' '[broken](nonexistent.md)' >> .agents/skills/probe/SKILL.md
                git add .agents/skills/probe/SKILL.md
                if "$runner" run agent-docs --config "$hook_config" --files .agents/skills/probe/SKILL.md; then
                  echo 'agent-docs hook accepted a broken relative link' >&2
                  exit 1
                fi

                printf '%s\n' '# Example' "" '* item' > README.md
                git add README.md
                if "$runner" run format --config "$hook_config" --files README.md; then
                  echo 'format hook did not report a formatting change' >&2
                  exit 1
                fi
                grep -q -- '- item' README.md
                git add README.md
                "$runner" run format --config "$hook_config" --files README.md

                # ShellCheck still covers executable scripts without a .sh extension.
                printf '%s\n' '#!/usr/bin/env bash' 'echo $UNQUOTED' > probe-shell
                chmod +x probe-shell
                git add probe-shell
                if "$runner" run shellcheck --config "$hook_config" --files probe-shell; then
                  echo 'shellcheck missed an extensionless shell script' >&2
                  exit 1
                fi
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
                  pkgs.shellcheck
                ];
              }
              ''
                shellcheck --shell=bash ${inputs.self.apps.x86_64-linux.deploy.program}
                shellcheck --shell=bash ${inputs.self.apps.x86_64-linux.deploy-rs.program}
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

                python3 ${./scripts}/fleet-update.test.py ${./scripts/fleet-update.sh}
                python3 ${./scripts/fleet-readiness.test.py} ${./scripts/fleet-readiness-probe.sh} ${./scripts/fleet-readiness-deliver.sh}
                python3 ${./scripts/fleet-reboot-required.test.py} ${./scripts/fleet-reboot-required.sh}
                python3 ${./scripts/fleet-headless-reboot.test.py} ${./scripts/fleet-headless-reboot.sh}
                python3 ${./scripts/pi-generation-retention.test.py} ${./scripts/pi-generation-retention.py}
                python3 ${./scripts/package-update-event.test.py} ${./scripts/package-update-event.py}
                python3 ${./scripts/lock-update.test.py} ${inputs.self}/.github/workflows/lock-update.yml ${inputs.self}/.github/workflows/ci.yml ${inputs.self}/.github/workflows/revision-validation.yml
                touch $out
              '';

          bttoggle = pkgs.runCommand "check-bttoggle" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
            shellcheck --shell=bash ${./scripts/bttoggle.sh}
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
                builtins.hasAttr "grafana.${domain}" edgeTunnel.ingress
                && builtins.hasAttr "metrics.${domain}" edgeTunnel.ingress
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
