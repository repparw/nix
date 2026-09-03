{ config, lib, ... }:
let
  cfg = config.modules.services;
  prefix = cfg.bridgePrefix;
  hostName = config.networking.hostName or "";
  localContainers = lib.filterAttrs (_: s: s.host == hostName && s.container) cfg.definitions;
  names = lib.sort lib.lessThan (builtins.attrNames localContainers);
  all = lib.sort lib.lessThan (names ++ (lib.optional (hostName == "epsilon") "hermes"));
  alloc = lib.listToAttrs (
    lib.imap0 (i: name: lib.nameValuePair name "${prefix}.${toString (i + 2)}") all
  );
in
{
  config = lib.mkIf (all != [ ]) {
    containers = lib.mapAttrs (name: addr: {
      hostAddress = lib.mkDefault "${prefix}.1";
      localAddress = lib.mkDefault addr;
    }) alloc;
  };
}
