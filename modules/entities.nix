{ ... }:
{
  # Fleet topology only. Den resolves repparw@<host> before repparw.
  den.hosts = {
    x86_64-linux.alpha = {
      serviceAddress = "192.168.0.18";
      users.repparw = { };
    };

    aarch64-linux = {
      epsilon = {
        serviceAddress = "10.5.5.3";
        sshAddress = "146.181.42.97";
        users.repparw = { };
      };

      pi = {
        serviceAddress = "192.168.0.4";
        users.repparw = { };
      };
    };
  };
}
