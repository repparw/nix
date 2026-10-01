{ den, ... }:
{
  den.aspects.nixos-services.provides.matrizApi = {
    service-registry = {
      name = "finance";
      definition = {
        hostname = "finance";
        port = 3000;
        auth = "one_factor";
      };
    };

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
