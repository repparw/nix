{ den, ... }:
{
  den.aspects.ai.provides.voxtype-graphical-workaround = {
    homeManager =
      { lib, ... }:
      {
        systemd.user.services.voxtype = {
          Unit = {
            PartOf = [ "graphical-session.target" ];
            After = [ "graphical-session.target" ];
          };
          Install.WantedBy = lib.mkForce [ "graphical-session.target" ];
        };
      };
  };
}
