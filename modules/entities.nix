{ ... }:
{
  den.hosts = {
    x86_64-linux.alpha = {
      serviceAddress = "100.80.210.20";
      sshAddress = "192.168.0.18";
      users.repparw = { };
    };

    aarch64-linux = {
      epsilon = {
        serviceAddress = "100.98.41.63";
        users.repparw = { };
      };

      pi = {
        serviceAddress = "100.75.79.3";
        sshAddress = "192.168.0.4";
        users.repparw = { };
      };
    };
  };
}
