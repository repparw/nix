{ ... }:
{
  den.hosts = {
    x86_64-linux.alpha = {
      location = "home";
      serviceAddress = "100.80.210.20";
      sshAddress = "192.168.0.18";
      users.repparw = { };
    };

    aarch64-linux = {
      epsilon = {
        location = "cloud";
        serviceAddress = "100.98.41.63";
        users.repparw = { };
      };

      pi = {
        location = "home";
        serviceAddress = "100.75.79.3";
        sshAddress = "192.168.0.4";
        users.repparw = { };
      };
    };
  };
}
