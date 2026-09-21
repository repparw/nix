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
              {
                networking.nameservers = [
                  "1.1.1.1"
                  "9.9.9.9"
                ];

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
