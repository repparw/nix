{
  den,
  lib,
  ...
}:
let
  sshAddresses = lib.mapAttrs (_: host: host.sshAddress or host.serviceAddress) (
    lib.concatMapAttrs (_system: hosts: hosts) den.hosts
  );
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

        settings =
          lib.mapAttrs (_: hostname: {
            HostName = hostname;
            User = config.home.username;
          }) sshAddresses
          // {
            tv = {
              HostName = "192.168.0.48";
              User = "root";
            };
          };
      };
    };
  };
}
