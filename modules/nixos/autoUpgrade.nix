{ lib, inputs, ... }:
let
  allInputs = lib.attrNames inputs;

  updateFlags = lib.concatMap (input: [
    "--update-input"
    input
  ]) allInputs;
in
{
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    flags = updateFlags ++ [ "--commit-lock-file" ];
  };
}
