{
  inputs,
  ...
}:
{
  den.aspects.secrets = {
    nixos = { ... }: {
      sops = {
        defaultSopsFile = ../../secrets/secrets.yaml;
        defaultSopsFormat = "yaml";
      };

      sops.age.sshKeyPaths = [ "/home/repparw/.ssh/id_ed25519" ];

      sops.secrets = {
        accessTokens = {
          mode = "0440";
          owner = "repparw";
        };
      };
    };
  };
}
