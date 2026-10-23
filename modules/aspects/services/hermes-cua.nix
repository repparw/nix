{ inputs, ... }:
{
  den.aspects.hermes-cua.nixos = {
    containers.hermes.config = import ./hermes-cua/_module.nix {
      source = inputs.hermes-agent;
      ref =
        (builtins.fromJSON (builtins.readFile ../../../flake.lock)).nodes.hermes-agent.original.ref or "";
    };
  };
}
