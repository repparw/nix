{
  den,
  ...
}:
let
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGd04EwDYl0a0RAS16wbDI4K2cfHFM8guXXYZdH3XtX u0_a426@localhost #termux"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR t440"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH ubritos@gmail.com #alpha"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ+8tggqG7gvN3aWLkS9fw7oeX/4mAUhn/zj3uiZx63H repparw@pi #pi (also GitHub auth key)"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPNDUcUqc2o35+mlAwD1G9hDr/v2eAylEMBAuBX3rYnl repparw@epsilon #epsilon"
  ];
in
{
  den.aspects.ssh = {
    user = {
      openssh.authorizedKeys.keys = authorizedKeys;
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

          # Rooted webOS TV: webosbrew dropbear. Each host enlists its default
          # ~/.ssh/id_ed25519 in the TV's authorized_keys like any other machine.
          tv = {
            HostName = "192.168.0.48";
            User = "root";
          };
        };
      };
    };
  };
}
