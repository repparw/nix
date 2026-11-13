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
          # Cloudflare Tunnel serves this public URL on the remote edge.
          probePublicRoute = true;
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
                # The integration's v2.45.0 manifest pins tplinkrouterc6u
                # 5.38.0, which needs the stale smart_network client fix.
                # Upstream fixed it in v5.39.0 (TP-Link-Archer-C6U#260).
                # Drop the patch when the integration accepts v5.39.0.
                tplinkrouterc6u-patched =
                  pkgs.home-assistant.python3Packages.callPackage ../../_packages/tplinkrouterc6u.nix
                    { };
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
                    ps: with ps; [
                      aiogithubapi # hacs
                      aiofiles
                      jinja2
                      joserfc # auth_oidc
                      anthropic
                      litellm
                      pyyaml # ai_automation_suggester
                      pkgs.openssh
                    ];
                };
                networking.firewall.allowedTCPPorts = [ 8123 ];
              };
          };
        };
    };
}
