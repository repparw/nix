{ den, ... }:
{
  den.aspects.system = {
    nixos =
      { config, pkgs, ... }:
      {
        i18n.defaultLocale = "en_IE.UTF-8";
        i18n.extraLocaleSettings.LC_MONETARY = "es_AR.UTF-8";

        time.timeZone = "America/Argentina/Buenos_Aires";
        # Chromium/QtWebEngine apps (e.g. zapzap/WhatsApp) show UTC times unless
        # TZ is explicitly exported, even with correct /etc/localtime.
        environment.variables.TZ = config.time.timeZone;

        security = {
          rtkit.enable = true;
          polkit.enable = true;
          sudo.extraConfig = ''
            Defaults env_keep += "SUDO_ASKPASS"
            Defaults timestamp_timeout=60
            Defaults timestamp_type=global
          '';
        };

        services.earlyoom.enable = true;

        environment.systemPackages = with pkgs; [ openssh-askpass ];
        environment.variables = {
          SUDO_ASKPASS = "${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass";
          NIXOS_OZONE_WL = "1";
        };

      };
  };
}
