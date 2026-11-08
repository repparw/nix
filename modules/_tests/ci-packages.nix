{ pkgs }:
let
  inherit (pkgs) lib;
  config = {
    environment.systemPackages = [ pkgs.hello ];
    home-manager.users.user.home.packages = [ pkgs.coreutils ];
    services = {
      enabled = {
        enable = true;
        package = pkgs.bash;
      };
      disabled = {
        enable = false;
        package = throw "disabled package forced";
      };
      removed = throw "removed compatibility service forced";
    };
    containers.inner.config = {
      environment.systemPackages = [ pkgs.gnugrep ];
      services = { };
      containers = { };
    };
    system.build.toplevel = throw "system assembly must never be a CI package target";
  };
  options.services = {
    enabled = {
      enable.visible = true;
      package.visible = true;
    };
    disabled = {
      enable.visible = true;
      package.visible = true;
    };
    removed = {
      enable.visible = false;
      package.visible = false;
    };
  };
  host = system: {
    inherit options;
    config = lib.recursiveUpdate config { nixpkgs.hostPlatform.system = system; };
  };
  module = import ../ci-packages.nix {
    inherit lib;
    inputs.self.nixosConfigurations = {
      alpha = host "x86_64-linux";
      pi = host "aarch64-linux";
      epsilon = host "aarch64-linux";
    };
  };
  paths = system: map (package: package.drvPath) (lib.attrValues module.flake.ciPackages.${system});
  expected = map (package: package.drvPath) [
    pkgs.hello
    pkgs.coreutils
    pkgs.bash
    pkgs.gnugrep
  ];
in
assert lib.sort builtins.lessThan (paths "x86_64-linux") == lib.sort builtins.lessThan expected;
assert
  lib.sort builtins.lessThan (paths "aarch64-linux")
  == lib.sort builtins.lessThan (expected ++ expected);
pkgs.runCommand "check-ci-package-targets" { } "touch $out"
