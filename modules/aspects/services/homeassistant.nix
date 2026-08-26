{
  ...
}:
{
  den.aspects.nixos-services.provides.homeassistant =
    { ... }:
    {
      nixos = {
        # Home Assistant in nspawn; trial validated 2026-08-22, replacing the
        # earlier rootless-podman quadlet pod (removed together with its
        # hostPort-80 bind when Traefik took over ingress).
        containers.homeassistant = {
          autoStart = true;
          privateNetwork = true;
          hostAddress = "10.231.136.1";
          localAddress = "10.231.136.2";
          bindMounts."/var/lib/hass" = {
            hostPath = "/home/repparw/services/hass";
            isReadOnly = false;
          };
          config =
            { pkgs, ... }:
            {
              # nspawn breaks host-resolved (loopback stub); use the pi's own
              # LAN resolver over the bridge.
              networking.useHostResolvConf = false;
              networking.nameservers = [ "192.168.0.4" ];

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
              system.stateVersion = "26.05";
            };
        };
      };
    };
}
