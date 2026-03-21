{ lib, ... }:
{
  den.schema.user.classes = lib.mkDefault [ "homeManager" ];

  den.hosts.x86_64-linux = {
    alpha.users.repparw = { };
    beta.users.repparw = { };
  };
}
