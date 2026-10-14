{ den, ... }:
{
  den.aspects.passwordless-sudo.nixos.security.sudo.extraRules = [
    {
      users = [ "repparw" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
