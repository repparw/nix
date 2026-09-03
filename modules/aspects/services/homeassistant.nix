{
  ...
}:
{
  den.aspects.nixos-services.provides.homeassistant =
    { ... }:
    {
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
          # Home Assistant in nspawn (bridge addresses auto-allocated).
          networking.firewall.interfaces.eth0.allowedTCPPorts = [ hassPort ];
          containers.homeassistant = servicesLib.mkContainer {
            inherit cfg;
            name = "homeassistant";
            # Reached over host port-forwarding, not the bridge, so this
            # container keeps its own reachability model.
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
                # The pi LAN resolver was decommissioned, so resolve straight
                # out the masqueraded bridge via public DNS instead of the
                # bridge gateway mkContainer defaults to.
                networking.nameservers = [
                  "1.1.1.1"
                  "9.9.9.9"
                ];

                # shell_command.set_tv_backlight_mode pushes backlight modes to
                # the TV; the nspawn unit PATH omits system packages, so the
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
                    # discovered from the migrated instance's entity registry
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
                      # The TV backlight automation shells out to ssh (forced
                      # command on the TV's webosbrew key).
                      pkgs.openssh
                    ];
                };
                networking.firewall.allowedTCPPorts = [ 8123 ];
              };
          };
        };
    };
}
