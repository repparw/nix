{
  den,
  ...
}:
{
  # Vendor firmware updates via LVFS (SSDs, docks, peripherals, UEFI
  # capsules). Only meaningful on hosts with fwupd-discoverable devices:
  # alpha and beta hardware. pi is an SD-boot SBC and epsilon a VPS —
  # neither exposes LVFS devices, so they stay off this aspect.
  den.aspects.nixos-services.provides.firmware = {
    nixos = {
      services.fwupd.enable = true;
    };
  };
}
