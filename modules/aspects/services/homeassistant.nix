{
  ...
}:
{
  den.aspects.nixos-services.provides.homeassistant =
    { ... }:
    {
      service-registry = {
        name = "homeassistant";
        definition = {
          hostname = "home";
          container = true;
          port = 8123;
          auth = "bypass";
          monitor = true;
        };
      };

      nixos =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.modules.services;
          servicesLib = import ../../_services/lib.nix { inherit lib pkgs; };
          hassPort = 8123;
        in
        {
          networking.firewall.interfaces.eth0.allowedTCPPorts = [ hassPort ];
          containers.homeassistant = servicesLib.mkContainer {
            inherit cfg;
            name = "homeassistant";
            forwardPorts = [
              {
                containerPort = hassPort;
                hostPort = hassPort;
                protocol = "tcp";
              }
            ];
            bindMounts."/var/lib/hass" = {
              hostPath = "/home/repparw/services/hass";
              isReadOnly = false;
            };
            extraConfig =
              { pkgs, ... }:
              let
                # Upstream workaround: tplinkrouterc6u 5.38.0 merges stale
                # smart_network history entries (onlineTime 0) into the
                # active-client list, so a phone that left Wi-Fi stays in the
                # inventory and its tracker remains "home". The patch skips
                # those entries; the AX23 v2 SG response carries no explicit
                # online flag (the TL-XDR6088 issue upstream closed without
                # merging #107). Retire the patch and switch to the nixpkgs
                # package once upstream stops merging onlineTime-0
                # smart_network-only clients (AlexandrErohin/
                # TP-Link-Archer-C6U#106 tracks the related behavior).
                # Named "-patched" so a future nixpkgs
                # python3Packages.tplinkrouterc6u cannot shadow it in the
                # extraPackages with-scope.
                tplinkrouterc6u-patched = pkgs.python3Packages.callPackage ../../_packages/tplinkrouterc6u.nix { };
              in
              {
                # The nspawn unit PATH omits system packages, so the
                # ssh binary must be added to the service path explicitly.
                systemd.services.home-assistant.path = [ pkgs.openssh ];

                services.home-assistant = {
                  enable = true;
                  configDir = "/var/lib/hass";
                  extraComponents = [
                    "default_config"
                    "wake_on_lan"
                    "google_assistant"
                    "met"
                    "radio_browser"
                    "google_translate"
                    "tuya"
                    "webostv"
                    "wled"
                    "workday"
                    "google_drive"
                  ];
                  customComponents =
                    with pkgs.home-assistant-custom-components;
                    [
                      auth_oidc
                      adaptive_lighting
                    ]
                    ++ [
                      # Device_tracker presence from the router; replaces the
                      # HACS-managed install tested live. The config entry
                      # (credentials, 60 s polling, 300 s offline timeout)
                      # stays in the host storage.
                      (pkgs.callPackage ../../_packages/tplink-router-ha.nix {
                        tplinkrouterc6u = tplinkrouterc6u-patched;
                      })
                    ];
                  extraPackages =
                    ps:
                    with ps;
                    [
                      aiogithubapi # hacs
                      aiofiles
                      jinja2
                      joserfc # auth_oidc
                      anthropic
                      litellm
                      pyyaml # ai_automation_suggester
                      pkgs.openssh
                    ]
                    ++ [
                      tplinkrouterc6u-patched # tplink_router
                    ];
                };
                networking.firewall.allowedTCPPorts = [ 8123 ];
              };
          };
        };
    };
}
