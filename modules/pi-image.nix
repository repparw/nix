{ inputs, lib, ... }:
let
  image =
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
            environment.persistence."/persist".files = lib.mkForce [ "/etc/machine-id" ];
          }
        )
      ];
    }).config;
in
{
  perSystem =
    { system, pkgs, ... }:
    {
      checks.pi-image-configuration =
        assert
          map (entry: entry.file) image.environment.persistence."/persist".files == [ "/etc/machine-id" ];
        assert image.fileSystems."/".fsType == "tmpfs";
        assert image.sdImage.nixPathRegistrationFile == "/persist/nix-path-registration";
        assert !image.sdImage.expandOnBoot;
        assert !image.modules.persistence.mutableAccounts && !image.users.mutableUsers;
        assert !image.systemd.timers.fleet-deploy.enable && !image.systemd.timers.fleet-alpha-retry.enable;
        pkgs.writeText "pi-image-configuration.json" (
          builtins.toJSON {
            persistedFiles = map (entry: entry.file) image.environment.persistence."/persist".files;
            registrationPath = image.sdImage.nixPathRegistrationFile;
            rootFilesystem = image.fileSystems."/".fsType;
          }
        );
    }
    // lib.optionalAttrs (system == "aarch64-linux") {
      packages.pi-sd-image = image.system.build.sdImage;
    };
}
