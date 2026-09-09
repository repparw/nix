{ den, ... }:
{
  # Fleet topology only. Host implementations live in modules/hosts/ and
  # reusable user capabilities live in modules/aspects/. serviceAddress is the
  # address other fleet hosts use to reach services owned by that host.
  den.hosts = {
    x86_64-linux.alpha = {
      serviceAddress = "192.168.0.18";
      users.repparw.aspect = {
        includes = [
          den.aspects.repparw
          den.aspects.desktop
          den.aspects.gaming
          den.aspects.streaming
          den.aspects.cliamp
        ];
      };
    };

    aarch64-linux = {
      epsilon = {
        serviceAddress = "10.5.5.3";
        users.repparw.aspect = den.aspects.repparw;
      };

      pi = {
        serviceAddress = "192.168.0.4";
        users.repparw.aspect = {
          includes = [
            den.aspects.repparw
            den.aspects.ai._.t3code-split
          ];
        };
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