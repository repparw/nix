{ den, ... }:
{
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
        sshAddress = "146.181.42.97";
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
}
