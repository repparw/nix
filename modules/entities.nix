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
          den.aspects.moonshine-pr227-test
          den.aspects.ai._.t3code-nightly
          den.aspects.ai._.opencode-v2-primary
        ];
      };
    };

    aarch64-linux = {
      epsilon = {
        serviceAddress = "10.5.5.3";
        sshAddress = "146.181.42.97";
        users.repparw.aspect = {
          includes = [
            den.aspects.repparw
            den.aspects.ai._.t3code-split
            den.aspects.ai._.opencode-v2-primary
            den.aspects.ai._.t3code-nightly
          ];
        };
      };

      pi = {
        serviceAddress = "192.168.0.4";
        users.repparw.aspect = {
          includes = [
            den.aspects.repparw
            den.aspects.ai._.t3code-split
            den.aspects.ai._.opencode-v2-primary
            den.aspects.ai._.t3code-nightly
          ];
        };
      };
    };
  };
}
