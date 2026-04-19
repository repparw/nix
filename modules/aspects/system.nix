{ den, ... }:
{
  den.aspects.system = {
    nixos =
      { pkgs, ... }:
      {
        services.dbus.implementation = "broker";

        i18n.defaultLocale = "en_IE.UTF-8";

        time.timeZone = "America/Argentina/Buenos_Aires";

        security = {
          rtkit.enable = true;
          polkit.enable = true;
          sudo.extraConfig = ''
            Defaults env_keep += "SUDO_ASKPASS"
          '';
        };

        environment.systemPackages = with pkgs; [ openssh-askpass ];
        environment.variables.SUDO_ASKPASS = "${pkgs.openssh-askpass}/libexec/gtk-ssh-askpass";

        hardware.bluetooth.enable = true;
      };
  };
}
