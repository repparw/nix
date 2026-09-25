{ inputs, ... }:
let
  uv2nixRev = "5a836d395cbf5fc22670eb98dd4aa4fc4d406977";
  pyprojectNixRev = "e3b599ca2e7fcf93d4edf65d7f19bbf6491724f3";
  buildSystemsRev = "62c0d86027edb1c4f39a5facc09876348144f7c9";
in
{
  flake-file.inputs = {
    uv2nix = {
      url = "github:pyproject-nix/uv2nix/${uv2nixRev}";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
      };
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix/${pyprojectNixRev}";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs/${buildSystemsRev}";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
      };
    };
  };

  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      version = "2.0.2.6";
      openalgoRev = "732e208b90faf83ce69fc83da14f245309d82f60";

      # OpenAlgo is an application tree rather than an installable Python
      # package. Pin the exact release commit; uv2nix consumes its pyproject
      # and uv.lock while the launcher syncs the application tree into a
      # writable state directory.
      openalgoSrc = builtins.fetchGit {
        url = "https://github.com/marketcalls/openalgo.git";
        rev = openalgoRev;
        shallow = true;
      };

      workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = openalgoSrc;
      };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      pythonSet =
        (pkgs.callPackage inputs.pyproject-nix.build.packages {
          python = pkgs.python312;
        }).overrideScope
          (
            lib.composeManyExtensions [
              inputs.pyproject-build-systems.overlays.default
              overlay
            ]
          );

      venv = pythonSet.mkVirtualEnv "openalgo-${version}-env" workspace.deps.default;

      package =
        (pkgs.writeShellApplication {
          name = "openalgo";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.rsync
          ];
          text = ''
            state_root="''${OPENALGO_STATE_DIR:-''${XDG_STATE_HOME:-$HOME/.local/state}/openalgo}"
            app_root="$state_root/app"
            source_marker="$app_root/.nix-source"

            mkdir -p "$app_root"

            if [[ ! -f "$source_marker" ]] || [[ "$(<"$source_marker")" != "${openalgoRev}" ]]; then
              # Upstream assumes the checkout itself is writable. Keep its
              # source in the Nix store, but mirror it into persistent state
              # on version changes while preserving runtime data.
              ${pkgs.rsync}/bin/rsync -a --delete \
                --exclude='.env' \
                --exclude='/db/' \
                --exclude='/keys/' \
                --exclude='/log/' \
                --exclude='/logs/' \
                --exclude='/tmp/' \
                --exclude='/workspace/' \
                --exclude='/strategies/scripts/' \
                --exclude='/strategies/indicators/' \
                --exclude='/strategies/strategy_configs.json' \
                ${openalgoSrc}/ "$app_root/"

              printf '%s\n' "${openalgoRev}" > "$source_marker"
            fi

            mkdir -p \
              "$app_root/db" \
              "$app_root/keys" \
              "$app_root/log" \
              "$app_root/logs" \
              "$app_root/tmp" \
              "$app_root/workspace" \
              "$app_root/strategies/scripts" \
              "$app_root/strategies/indicators"

            if [[ ! -e "$app_root/.env" ]]; then
              cp "$app_root/.sample.env" "$app_root/.env"
              chmod 600 "$app_root/.env"
            fi

            cd "$app_root"
            export PYTHONDONTWRITEBYTECODE=1
            unset PYTHONPATH

            exec ${venv}/bin/python app.py "$@"
          '';
        }).overrideAttrs
          (old: {
            passthru = (old.passthru or { }) // {
              inherit openalgoSrc venv;
              sourceRev = openalgoRev;
            };
            meta = (old.meta or { }) // {
              description = "Broker-agnostic open-source trading automation platform";
              homepage = "https://github.com/marketcalls/openalgo";
              license = lib.licenses.agpl3Only;
              mainProgram = "openalgo";
              platforms = lib.platforms.linux;
            };
          });
    in
    {
      packages.openalgo = package;

      apps.openalgo = {
        type = "app";
        program = "${package}/bin/openalgo";
        meta.description = "Run OpenAlgo with persistent per-user state";
      };
    };
}
