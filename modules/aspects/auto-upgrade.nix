{
  inputs,
  lib,
  ...
}:
let
  allInputs = lib.attrNames inputs;
  updateFlags = lib.concatMap (input: [
    "--update-input"
    input
  ]) allInputs;
in
{
  den.aspects.auto-upgrade = {
    nixos = {
      system.autoUpgrade = {
        enable = true;
        flake = inputs.self.outPath;
        flags = updateFlags ++ [ "--commit-lock-file" ];
      };
    };
  };
}
