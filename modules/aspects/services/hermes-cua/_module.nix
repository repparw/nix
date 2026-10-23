{ source, ref }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  runtime = pkgs.callPackage ../../../_packages/cua.nix {
    python3Packages = config.services.hermes-agent.package.python.pkgs;
  };
  integration = import ./_integration.nix {
    inherit
      lib
      source
      ref
      runtime
      ;
  };
in
{
  options.modules.hermes-cua.ready = lib.mkOption {
    type = lib.types.bool;
    readOnly = true;
    internal = true;
    default = integration.ready;
  };
  config.services.hermes-agent = lib.mkIf integration.ready {
    settings = integration.settings;
    extraPlugins = [ (pkgs.callPackage ../../../_packages/hermes-cua-spaces.nix { }) ];
    extraPythonPackages = [ runtime ];
    extraPackages = [ runtime ];
  };
}
