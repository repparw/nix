{
  den,
  ...
}:
{
  den.aspects.vms = {
    includes = [ ];

    nixos = { pkgs, lib, config, ... }: {
      virtualisation.libvirtd = {
        onBoot = "ignore";
        onShutdown = "ignore";
      };
    };
  };
}
