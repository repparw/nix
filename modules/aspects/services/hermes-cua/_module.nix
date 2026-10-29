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
  options.modules.hermes-cua = {
    enable = lib.mkEnableOption "the remote CUA Spaces backend for Hermes";
    ready = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      internal = true;
      default = config.modules.hermes-cua.enable && integration.ready;
    };
  };
  config.assertions = [
    {
      assertion = !config.modules.hermes-cua.enable || integration.ready;
      message = "Hermes CUA was explicitly enabled without a compatible source and SDK; leave it disabled until enrollment and validation are complete.";
    }
  ];
  config.services.hermes-agent = lib.mkIf config.modules.hermes-cua.ready {
    settings = integration.settings;
    extraPlugins = [ (pkgs.callPackage ../../../_packages/hermes-cua-spaces.nix { }) ];
    extraPythonPackages = [ runtime ];
    extraPackages = [ runtime ];
  };
}
