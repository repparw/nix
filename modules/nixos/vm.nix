{
  lib,
  config,
  ...
}: let
  cfg = config.modules.vm;
in {
  options.modules.vm = {
    enable = lib.mkEnableOption "vm setup";
  };

  config = lib.mkIf cfg.enable {
    programs.virt-manager.enable = true;

    users.groups.libvirtd.members = ["repparw"];

    virtualisation.libvirtd.enable = true;

    virtualisation.spiceUSBRedirection.enable = true;
  };
}
