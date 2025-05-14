{
  modulesPath,
  lib,
  ...
}: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  networking.networkmanager.enable = lib.mkForce false;

  isoImage.squashfsCompression = "gzip -Xcompression-level 1";
}
