{
  pkgs,
  inputs,
  ...
}:
{
  den.aspects.nixos-base = {
    nixos =
      { pkgs, ... }:
      {
        imports = [
          inputs.nix-index-database.nixosModules.nix-index
          inputs.home-manager.nixosModules.home-manager
          inputs.stylix.nixosModules.stylix
        ];

        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "hm-backup";
        };

        nixpkgs.overlays =
          let
            pkgsDir = ../../pkgs;
            allPkgs =
              if builtins.pathExists pkgsDir then builtins.attrNames (builtins.readDir pkgsDir) else [ ];
            mkPkgOverlay = name: final: prev: {
              ${name} = final.callPackage (pkgsDir + "/${name}") { };
            };
            cfaitOverlay = final: prev: {
              cfait = inputs.nixpkgs-pr.legacyPackages.${prev.stdenv.hostPlatform.system}.cfait;
            };
          in
          [
            (final: prev: {
              neovim = inputs.nixvim-config.packages.${prev.stdenv.hostPlatform.system}.default;
              wshowkeys = prev.wshowkeys.overrideAttrs (old: {
                src = prev.fetchFromGitHub {
                  owner = "repparw";
                  repo = "wshowkeys";
                  rev = "52d1191cc250d3a24b83f77ce23f23d498c23bb3";
                  hash = "sha256-BkmB+/oG0tsAbvAjkoEAJxObjvg+mCENhM4EHDDXQAI=";
                };
              });
            })
            inputs.firefox-addons.overlays.default
            cfaitOverlay
          ]
          ++ (map mkPkgOverlay allPkgs);

        nixpkgs.config.allowUnfree = true;

        programs.nix-index-database.comma.enable = true;

        users.users.repparw = {
          isNormalUser = true;
          openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGd04EwDYl0a0RAS16wbDI4K2cfHFM8guXXYZdH3XtX u0_a426@localhost #termux"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR t440"
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH ubritos@gmail.com #alpha"
          ];
          shell = pkgs.fish;
          linger = true;
          initialHashedPassword = "$y$j9T$WPuWlgd7OQOePD8XKqNVv0$Pe9XhFT2hKh1YnyDVHxEwOe.IYTMr8K4JUtxBVjEza/";
          description = "repparw";
          extraGroups = [
            "adbusers"
            "wheel"
          ];
        };

        users.users.root.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGd04EwDYl0a0RAS16wbDI4K2cfHFM8guXXYZdH3XtX u0_a426@localhost #termux"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR t440"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH ubritos@gmail.com #alpha"
        ];

        systemd.network = {
          enable = true;
          wait-online.enable = false;
          links."40-eth0" = {
            matchConfig.OriginalName = "eth0";
            linkConfig.WakeOnLan = "magic";
          };
          networks = {
            "10-eth" = {
              matchConfig.Name = "eth0";
              address = [ "192.168.0.18/24" ];
              routes = [ { Gateway = "192.168.0.1"; } ];
              dns = [
                "1.1.1.1"
                "1.0.0.1"
              ];
              linkConfig.RequiredForOnline = "routable";
            };
            "20-wifi" = {
              matchConfig.Name = "wlan0";
              linkConfig.RequiredForOnline = "no";
              networkConfig = {
                DHCP = "yes";
                Domains = "~.";
              };
              dhcpV4Config.RouteMetric = 3000;
            };
          };
        };

        networking = {
          wireless.iwd = {
            enable = true;
            settings = {
              General.AddressRandomization = "network";
              Settings.AutoConnect = true;
            };
          };
          useNetworkd = true;
          useDHCP = false;
          nftables.enable = true;
          usePredictableInterfaceNames = false;
          firewall = {
            interfaces.eth0 = {
              allowedTCPPorts = [
                80
                443
              ];
              allowedUDPPorts = [
                54535
              ];
            };
          };
          nameservers = [
            "1.1.1.1#cloudflare-dns.com"
            "1.0.0.1#cloudflare-dns.com"
          ];
        };

        services.dbus.implementation = "broker";

        services.resolved = {
          enable = true;
          settings.Resolve = {
            DNSSEC = true;
            DNSOverTLS = true;
          };
        };

        i18n.defaultLocale = "en_IE.UTF-8";

        nix = {
          settings = {
            extra-substituters = [
              "https://cachix.cachix.org"
              "https://devenv.cachix.org"
            ];
            extra-trusted-public-keys = [
              "cachix.cachix.org-1:eWNHQldwUO7G2VkjpnjDbWwy4KQ/HNxht7H4SSoMckM="
              "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
            ];

            use-xdg-base-directories = true;

            trusted-users = [
              "root"
            ];

            allowed-users = [
              "repparw"
            ];

            experimental-features = "nix-command flakes";

            commit-lock-file-summary = "flake.lock: Update";
          };

          optimise.automatic = true;
        };

        time.timeZone = "America/Argentina/Buenos_Aires";

        environment.systemPackages = [
          inputs.sops-nix.packages.${pkgs.stdenv.hostPlatform.system}.sops-import-keys-hook
        ];

        security = {
          rtkit.enable = true;
          polkit.enable = true;
        };

        hardware.bluetooth.enable = true;
      };
  };
}
