{ inputs, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      pi = inputs.self.nixosConfigurations.pi.config;
      services = pi.modules.services;
      lanHosts = pi.modules.lan-hosts.file;
      jellyfinHost = "${services.definitions.jellyfin.hostname}.${services.domain}";
      jellyfinEntry = "${services.hostSshAddresses.${services.lanEdgeHost}} ${jellyfinHost}";
    in
    {
      # Ship the same generated hosts mapping used by the fleet to the rooted
      # webOS TV. No duplicate IPs or domain names are maintained in the
      # device repository.
      packages.tv-lan-hosts = lanHosts;

      checks.tv-lan-hosts =
        pkgs.runCommand "check-tv-lan-hosts" { nativeBuildInputs = [ pkgs.gnugrep ]; }
          ''
            grep -Fqx ${lib.escapeShellArg jellyfinEntry} ${lanHosts}
            touch "$out"
          '';
    };
}
