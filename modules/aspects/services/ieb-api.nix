{ den, ... }:
{
  den.aspects.nixos-services.provides.iebApi = {
    nixos =
      { config, ... }:
      {
        sops.secrets = {
          iebUsername = {
            sopsFile = ../../../secrets/ieb.sops.yaml;
            owner = config.users.users.repparw.name;
            mode = "0400";
          };
          iebPassword = {
            sopsFile = ../../../secrets/ieb.sops.yaml;
            owner = config.users.users.repparw.name;
            mode = "0400";
          };
        };
      };
  };
}
