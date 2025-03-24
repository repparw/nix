{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  isoImage.squashfsCompression = "gzip -Xcompression-level 1";
}
