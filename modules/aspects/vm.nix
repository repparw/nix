{
  lib,
  ...
}:
{
  den.aspects.vm = {
    nixos =
      { config, ... }:
      {
        options.modules.vm = {
          enable = lib.mkEnableOption "vm setup";
        };

        config = lib.mkIf config.modules.vm.enable {
          programs.virt-manager.enable = true;

          users.groups.libvirtd.members = [ "repparw" ];

          virtualisation.libvirtd.enable = true;

          virtualisation.spiceUSBRedirection.enable = true;
        };
      };
  };
}
