{ inputs, lib, ... }:
{
  perSystem =
    { system, ... }:
    lib.optionalAttrs (system == "aarch64-linux") {
      packages.pi-sd-image =
        (inputs.self.nixosConfigurations.pi.extendModules {
          modules = [
            (inputs.nixpkgs + "/nixos/modules/installer/sd-card/sd-image-aarch64.nix")
            (
              { lib, ... }:
              {
                fileSystems."/" = lib.mkForce {
                  device = "tmpfs";
                  fsType = "tmpfs";
                  options = [
                    "x-initrd.mount"
                    "mode=0755"
                    "size=50%"
                  ];
                };
                boot.loader.grub.enable = lib.mkForce false;
                boot.loader.generic-extlinux-compatible.enable = lib.mkForce true;
                sdImage.nixPathRegistrationFile = "/persist/nix-path-registration";
                sdImage.expandOnBoot = false;
                systemd.timers.fleet-deploy.enable = false;
                systemd.timers.fleet-alpha-retry.enable = false;
                modules.persistence.mutableAccounts = lib.mkForce false;
                users.mutableUsers = lib.mkForce false;
              }
            )
          ];
        }).config.system.build.sdImage;
    };
}
