{ ... }:
{
  programs.virt-manager.enable = true;

  users.groups.libvirtd.members = [ "repparw" ];

  virtualisation.libvirtd.enable = true;

  virtualisation.spiceUSBRedirection.enable = true;
}
