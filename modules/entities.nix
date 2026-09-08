{ den, ... }:
{
  # Fleet topology only. Host implementations live in modules/hosts/ and
  # reusable user capabilities live in modules/aspects/.
  den.hosts = {
    x86_64-linux.alpha.users.repparw.aspect = {
      includes = [
        den.aspects.repparw
        den.aspects.desktop
        den.aspects.gaming
        den.aspects.streaming
      ];
    };

    aarch64-linux = {
      epsilon.users.repparw.aspect = den.aspects.repparw;
      pi.users.repparw.aspect = {
        includes = [
          den.aspects.repparw
          den.aspects.ai._.t3code-split
        ];
      };
    };
  };

  # Parked: no laptop using this host config. Re-enable when hardware is back.
  # den.hosts.x86_64-linux.beta.users.repparw.aspect = {
  #   includes = [
  #     den.aspects.repparw
  #     den.aspects.desktop
  #   ];
  # };
}
