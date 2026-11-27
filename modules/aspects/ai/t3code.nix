{
  den,
  lib,
  pkgs,
  ...
}:
{
  den.aspects.ai.provides.t3code = {
    # The Stylix theme is a style concern, but it follows this application.
    includes = [
      (den.lib.policy.when (
        { user, ... }: user.hasAspect den.aspects.style
      ) den.aspects.style.provides.t3code-theme)
    ];

    provides.to-hosts.nixos = {
      programs.nix-ld.enable = true;
    };

    homeManager =
      {
        lib,
        pkgs,
        config,
        ...
      }:
      let
        # T3 Code gives each Antigravity instance a private GEMINI_HOME and
        # deliberately does not link ~/.gemini/config/mcp_config.json into it
        # (pingdotgg/t3code discussion #13117), so the shared fleet servers
        # are installed into every profile by the runtime launcher. The file
        # must be a regular file: the text-generation gate rejects symlinks,
        # and any configured server disables Antigravity-backed background
        # text generation such as thread titles and commit messages
        # (pingdotgg/t3code issue #42608) — those helpers need another
        # system model once this config is present.
        fleetMcpServers = lib.filterAttrs (_: server: server.command != null) config.programs.mcp.servers;

        antigravityMcpConfig =
          if fleetMcpServers == { } then
            null
          else
            (pkgs.formats.json { }).generate "antigravity-profile-mcp-config.json" {
              mcpServers = lib.mapAttrs (_: server: {
                command = server.command;
                args = server.args;
                env = server.env;
              }) fleetMcpServers;
            };

        antigravityRuntime = pkgs.callPackage ../../_packages/antigravity-cli-runtime.nix {
          mcpConfig = antigravityMcpConfig;
        };

        providerInstances = {
          antigravity = {
            driver = "antigravity";
            enabled = true;
            config = {
              enabled = true;
              binaryPath = "${antigravityRuntime.runtime}/bin/agy";
            };
          };

          antigravity_2 = {
            driver = "antigravity";
            displayName = "Antigravity 2";
            enabled = true;
            config = {
              enabled = true;
              binaryPath = "${antigravityRuntime.runtime}/bin/agy";
            };
          };

          # Both Codex instances share one CODEX_HOME for settings and
          # models; the second account keeps its auth in the shadow home.
          codex = {
            driver = "codex";
            enabled = true;
            config = {
              enabled = true;
              binaryPath = "codex";
              homePath = "${config.xdg.configHome}/codex";
            };
          };

          codex_2 = {
            driver = "codex";
            displayName = "2";
            enabled = true;
            config = {
              enabled = true;
              setupMode = "existing";
              binaryPath = "codex";
              homePath = "${config.xdg.configHome}/codex";
              shadowHomePath = "${config.xdg.configHome}/codex-ubritos1";
            };
          };

          opencode = {
            driver = "opencode";
            enabled = true;
            config = {
              enabled = true;
              binaryPath = "${config.programs.opencode.package}/bin/opencode";
            };
          };
        };
      in
      {
        programs.t3code = {
          enable = true;
          package = lib.mkDefault (if pkgs ? t3code-desktop then pkgs.t3code-desktop else pkgs.t3code);

          userSettings.providerInstances = providerInstances;

          server = {
            enable = true;
            # The headless unit launches `opencode serve` children, and
            # home.sessionVariables only reach login sessions. Without this
            # file, OPENCODE_CONFIG reached the unit only when an interactive
            # session leaked it into the systemd user manager, so opencode
            # started without the declarative MCP layer after a reboot.
            environmentFile = pkgs.writeText "t3code-environment" (
              lib.concatStringsSep "\n" (
                [
                  "CODEX_HOME=${config.xdg.configHome}/codex"
                ]
                ++ lib.optional (
                  config.programs.opencode.enable && config.programs.opencode.mutableSettings
                ) "OPENCODE_CONFIG=${config.xdg.configHome}/opencode/home-manager.json"
                ++ lib.optional (
                  config.programs.opencode.tui != { }
                ) "OPENCODE_TUI_CONFIG=${config.xdg.configHome}/opencode/home-manager-tui.json"
              )
              + "\n"
            );
          };
        };
      };
  };

  # Desktop-session half of Connect: the launcher and the t3code:// handler
  # only matter where a graphical browser runs. Hosts pick this up through
  # aspect composition (den.aspects.desktop) instead of a capability flag.
  den.aspects.ai.provides.t3code-connect-desktop.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      launcher = pkgs.writeShellScriptBin "t3code-desktop-connect" ''
        export CODEX_HOME=${lib.escapeShellArg config.home.sessionVariables.CODEX_HOME}
        exec ${lib.getExe' config.programs.t3code.package "t3code-desktop"} "$@"
      '';
    in
    {
      home.packages = [ launcher ];

      # Browsers resolve URL schemes through GIO, which only consults
      # `mimeinfo.cache` associations when `mimeapps.list` names a default.
      # The app's own `xdg-mime default` call is skipped while Electron runs
      # unpackaged, so declare the handler instead of relying on runtime
      # registration.
      xdg.mimeApps = {
        enable = true;
        defaultApplications."x-scheme-handler/t3code" = "t3code.desktop";
      };

      xdg.desktopEntries.t3code = {
        name = "T3 Code (Alpha)";
        exec = "t3code-desktop-connect %U";
        icon = "t3code";
        settings.StartupWMClass = "t3code";
        categories = [ "Development" ];
        mimeType = [ "x-scheme-handler/t3code" ];
      };
    };
}
