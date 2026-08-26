# Minimal bootable SD card for the pi: our account, our shell, our SSH
# keys — but deliberately NOT the den host stack (its default aspects
# assume sops keys and a desktop-class user). Boot it, then pull the real
# system:
#
#   nixos-rebuild switch --flake github:repparw/nix#pi
#
# Built with:
#   nix build .#nixosConfigurations.pi-sd.config.system.build.sdImage
{
  inputs,
  ...
}:
{
  flake.nixosConfigurations.pi-sd = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      (
        { modulesPath, pkgs, ... }:
        {
          imports = [
            (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
          ];

          networking.hostName = "pi-sd";
          services.openssh.enable = true;
          programs.fish.enable = true;

          # Rescue card behind the LAN firewall: wheel sudo without a
          # password so headless restores never stall on a prompt.
          security.sudo.wheelNeedsPassword = false;

          users.mutableUsers = false;
          users.users.repparw = {
            isNormalUser = true;
            uid = 1000;
            description = "repparw";
            extraGroups = [ "wheel" ];
            shell = pkgs.fish;
            openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGd04EwDYl0a0RAS16wbDI4K2cfHFM8guXXYZdH3XtX u0_a426@localhost #termux"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR t440"
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH ubritos@gmail.com #alpha"
            ];
          };
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH ubritos@gmail.com #alpha"
          ];

          sdImage.compressImage = true;

          system.stateVersion = "26.05";
        }
      )
    ];
  };
}
