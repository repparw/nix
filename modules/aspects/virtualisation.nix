_: {
  den.aspects.virtualisation = {
    nixos = { config, ... }: {
      programs.virt-manager.enable = true;

      users.groups.libvirtd.members = [ config.users.users.repparw.name ];

      virtualisation.libvirtd.enable = true;
      virtualisation.spiceUSBRedirection.enable = true;
    };
  };

}
