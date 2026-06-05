{ den, ... }:
{
  den.aspects.system = {
    nixos =
      { pkgs, ... }:
      {
        i18n.defaultLocale = "en_IE.UTF-8";

        time.timeZone = "America/Argentina/Buenos_Aires";

        security = {
          rtkit.enable = true;
          polkit.enable = true;
          sudo.extraConfig = ''
            Defaults env_keep += "SUDO_ASKPASS"
            Defaults timestamp_timeout=60
            Defaults timestamp_type=ppid
          '';
        };

        environment.systemPackages = with pkgs; [ openssh-askpass ];
        environment.variables = {
          SUDO_ASKPASS = "${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass";
          NIXOS_OZONE_WL = "1";
        };

        hardware.bluetooth.enable = true;
      };
  };
}
