# Temporary semantic snapshot for the Den role refactor. Removed after review.
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
        sshEnabled = cfgAt [ "services" "openssh" "enable" ] false;
        moonshineEnabled = cfgAt [ "services" "moonshine" "enable" ] false;
        moonshineUser = cfgAt [ "services" "moonshine" "user" ] null;
        moonshinePackage = getName (cfgAt [ "services" "moonshine" "package" ] cfg.system.build.toplevel);
        moonshineSettings = cfgAt [ "services" "moonshine" "settings" ] { };
        steamEnabled = cfgAt [ "programs" "steam" "enable" ] false;
        gamemodeEnabled = cfgAt [ "programs" "gamemode" "enable" ] false;
        displayAutoLogin = cfgAt [ "services" "displayManager" "autoLogin" ] { };
        systemPackages = names cfg.environment.systemPackages;
        homeManagerSharedModules = builtins.length (cfgAt [ "home-manager" "sharedModules" ] [ ]);
        nixpkgsOverlayCount = builtins.length (cfgAt [ "nixpkgs" "overlays" ] [ ]);
        serviceNames = sorted (builtins.attrNames cfg.systemd.services);
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
