# Temporary three-host semantic snapshot for Den host-routing and service-inventory refactors.
{ flakePath }:
let
  flake = builtins.getFlake ("path:" + flakePath);
  lib = flake.inputs.nixpkgs.lib;
  at = path: fallback: attrs: lib.attrByPath path fallback attrs;
  getName = p: lib.getName p;
  names = xs: lib.sort builtins.lessThan (map getName xs);
  sorted = xs: lib.sort builtins.lessThan xs;
  mk = hostName:
    let
      cfg = flake.nixosConfigurations.${hostName}.config;
      user = cfg.users.users.repparw;
      hm = cfg.home-manager.users.repparw;
      hmAt = path: fallback: at path fallback hm;
      cfgAt = path: fallback: at path fallback cfg;
    in {
      host = hostName;
      account = {
        home = user.home;
        isNormalUser = user.isNormalUser;
        shell = toString user.shell;
        extraGroups = sorted user.extraGroups;
        linger = hmAt [ "systemd" "user" "startServices" ] "";
      };
      nixos = {
        fishEnabled = cfgAt [ "programs" "fish" "enable" ] false;
        opensshExtraConfig = cfgAt [ "services" "openssh" "extraConfig" ] "";
        gvfsEnabled = cfgAt [ "services" "gvfs" "enable" ] false;
        nixLdEnabled = cfgAt [ "programs" "nix-ld" "enable" ] false;
        nixLdLibraries = names (cfgAt [ "programs" "nix-ld" "libraries" ] [ ]);
        sopsSecretNames = sorted (builtins.attrNames (cfgAt [ "sops" "secrets" ] { }));
        obsidianSecretOwner =
          if hostName == "alpha" then cfg.sops.secrets.rcloneObsidianCrypt.owner else null;
        sshEnabled = cfgAt [ "services" "openssh" "enable" ] false;
        moonshineEnabled = cfgAt [ "services" "moonshine" "enable" ] false;
        moonshineUser = if hostName == "alpha" then cfg.services.moonshine.user else null;
        moonshinePackage = if hostName == "alpha" then getName cfg.services.moonshine.package else null;
        moonshineSettings = if hostName == "alpha" then cfg.services.moonshine.settings else { };
        steamEnabled = cfgAt [ "programs" "steam" "enable" ] false;
        gamemodeEnabled = cfgAt [ "programs" "gamemode" "enable" ] false;
        displayAutoLogin = if hostName == "alpha" then {
          enable = cfg.services.displayManager.autoLogin.enable;
          user = cfg.services.displayManager.autoLogin.user;
        } else null;
        systemPackages = names cfg.environment.systemPackages;
        homeManagerSharedModules = builtins.length (cfgAt [ "home-manager" "sharedModules" ] [ ]);
        nixpkgsOverlayCount = builtins.length (cfgAt [ "nixpkgs" "overlays" ] [ ]);
        serviceNames = sorted (builtins.attrNames cfg.systemd.services);
        serviceInventory = {
          hostAddresses = cfg.modules.services.hostAddresses;
          hostSshAddresses = cfg.modules.services.hostSshAddresses;
          definitions = lib.mapAttrs (_: service: {
            inherit (service)
              host hostname port publishedPort container monitor
              healthcheck auth lanEdge;
          }) cfg.modules.services.definitions;
        };
      };
      homeManager = {
        packages = names hm.home.packages;
        fish = {
          enable = hmAt [ "programs" "fish" "enable" ] false;
          shellAbbrs = hmAt [ "programs" "fish" "shellAbbrs" ] { };
          shellAliases = hmAt [ "programs" "fish" "shellAliases" ] { };
          plugins = map (x: x.name) (hmAt [ "programs" "fish" "plugins" ] [ ]);
          binds = hmAt [ "programs" "fish" "binds" ] { };
        };
        t3code = getName (hmAt [ "programs" "t3code" "package" ] cfg.system.build.toplevel);
        mangohud = hmAt [ "programs" "mangohud" "enable" ] false;
        xdgMimeDefaults = hmAt [ "xdg" "mimeApps" "defaultApplications" ] { };
        desktopEntryNames = sorted (builtins.attrNames (hmAt [ "xdg" "desktopEntries" ] { }));
        userServiceNames = sorted (builtins.attrNames (hmAt [ "systemd" "user" "services" ] { }));
        sessionVariables = hmAt [ "home" "sessionVariables" ] { };
      };
    };
in
  builtins.listToAttrs (map (host: { name = host; value = mk host; }) [ "alpha" "pi" "epsilon" ])
