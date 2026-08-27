{ den, ... }:
{
  # Workaround for upstream missing graphical-session.target ordering:
  # nixos-unstable's voxtype module historically used default.target, racing
  # amdgpu render node creation and pinning transcription to CPU. Local override
  # binds to graphical-session.target until the upstream PR lands.
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
