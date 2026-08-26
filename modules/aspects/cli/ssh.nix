{
  den,
  ...
}:
{
  den.aspects.ssh = {
    user = {
      openssh.authorizedKeys.keys = import ../../../authorized-keys.nix;
    };

    homeManager = { config, ... }: {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        settings = {
          pi = {
            HostName = "192.168.0.4";
            User = config.home.username;
          };

          alpha = {
            HostName = "192.168.0.18";
            User = config.home.username;
          };

          # Oracle Cloud Always Free A1 VPS (epsilon). Reserved public IP:
          # survives stop/start and reboots, unlike the launch-time ephemeral.
          epsilon = {
            HostName = "146.181.42.97";
            User = config.home.username;
          };

          # Rooted webOS TV: webosbrew dropbear, root key from webOS devmode.
          tv = {
            HostName = "192.168.0.48";
            User = "root";
            IdentityFile = "~/.ssh/webos_id_ed25519";
          };
        };
      };
    };
  };
}
