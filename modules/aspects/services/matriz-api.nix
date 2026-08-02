{ den, ... }:
{
  den.aspects.nixos-services.provides.matrizApi = {
    nixos =
      { config, ... }:
      {
        sops.secrets = {
          matrizApiUsername = {
            sopsFile = ../../../secrets/matriz.sops.yaml;
            owner = config.users.users.repparw.name;
            mode = "0400";
          };
          matrizApiPassword = {
            sopsFile = ../../../secrets/matriz.sops.yaml;
            owner = config.users.users.repparw.name;
            mode = "0400";
          };
          matrizApiAccount = {
            sopsFile = ../../../secrets/matriz.sops.yaml;
            owner = config.users.users.repparw.name;
            mode = "0400";
          };
        };
      };
  };
}
