{
  den,
  ...
}:
{
  den.aspects.nixos-services.provides.firmware = {
    nixos = {
      services.fwupd.enable = true;
    };
  };
}
