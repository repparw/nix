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
                # Keep the client package custom because it is not present in
                # the pinned nixpkgs. Upstream v5.40.0 includes the stale
                # smart_network history fix used by the AX23 v2 presence test.
                tplinkrouterc6u-custom =
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
                      # Home Assistant 2026.11 stores person data in a
                      # PersonData dataclass, but the auth_oidc tests still
                      # index it as a tuple and fail to build on aarch64 and
                      # x86_64. This is the upstream fix from NixOS/nixpkgs
                      # 961415f8cca2; drop the override once the locked
                      # nixpkgs contains that commit.
                      (auth_oidc.overrideAttrs (old: {
                        postPatch = (old.postPatch or "") + ''
                          substituteInPlace tests/test_hass_auth_provider.py \
                            --replace-fail "hass.data[PERSON_DOMAIN][1]" "hass.data[PERSON_DOMAIN].storage_collection"
                        '';
                      }))
                      adaptive_lighting
                    ]
                    ++ [
                      # Device_tracker presence from the router; replaces the
                      # HACS-managed install tested live. The config entry
                      # (credentials, 60 s polling, 300 s offline timeout)
                      # stays in the host storage.
                      (pkgs.callPackage ../../_packages/tplink-router-ha.nix {
                        tplinkrouterc6u = tplinkrouterc6u-custom;
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
                      tplinkrouterc6u-custom # tplink_router
                    ];
                };
                networking.firewall.allowedTCPPorts = [ 8123 ];
              };
          };
        };
    };
}
