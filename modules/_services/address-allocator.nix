{ config, lib, ... }:
# Assigns a deterministic bridge address to every privateNetwork container on
# this host, derived from the host's bridgePrefix (gateway .1, containers from
# .2, sorted by name).
#
# The container set is a per-host list, not derived from `config.containers`:
# defining a container's address in terms of `config.containers` is circular
# in the module system (infinite recursion). Keeping the registry's `host`
# field as the source would require restructuring how a service is declared
# "runs on host X" separately from "reachable via LAN vs container bridge".
# This list is the single place that maps host -> containers; add a container
# to a host here (and to the inventory) and it gets the next free address.
# `mkDefault` means an explicitly-pinned localAddress still wins.
let
  prefix = config.modules.services.bridgePrefix;
  host = config.networking.hostName or "";
  namesByHost = {
    alpha = [
      "bazarr"
      "jellyfin"
      "paperless"
      "prowlarr"
      "qbittorrent"
      "radarr"
      "sonarr"
    ];
    epsilon = [
      "authelia"
      "glance"
      "hermes"
      "miniflux"
    ];
    pi = [
      "archisteamfarm"
      "homeassistant"
    ];
  };
  names = namesByHost.${host} or [ ];
  alloc = lib.listToAttrs (
    lib.imap0 (i: name: lib.nameValuePair name "${prefix}.${toString (i + 2)}") (
      lib.sort lib.lessThan names
    )
  );
in
{
  config = lib.mkIf (names != [ ]) {
    containers = lib.mapAttrs (name: addr: {
      hostAddress = lib.mkDefault "${prefix}.1";
      localAddress = lib.mkDefault addr;
    }) alloc;
  };
}
