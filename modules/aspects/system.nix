{ ... }:
{
  den.aspects.system = {
    nixos =
      { ... }:
      {
        services.dbus.implementation = "broker";

        i18n.defaultLocale = "en_IE.UTF-8";

        time.timeZone = "America/Argentina/Buenos_Aires";

        security = {
          rtkit.enable = true;
          polkit.enable = true;
        };

        hardware.bluetooth.enable = true;
      };
  };
}
