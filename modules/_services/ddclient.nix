{
  config,
  lib,
  ...
}:
{
  users.users.ddclient = {
    isSystemUser = true;
    group = "ddclient";
  };
  users.groups.ddclient = { };

  systemd.services.ddclient.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "ddclient";
  };

  services.ddclient = {
    enable = true;
    protocol = "cloudflare";
    zone = "repparw.com";
    domains = [ "repparw.com" ];
    username = "token";
    passwordFile = config.sops.secrets.ddclientPassword.path;
    usev4 = "web, web=ifconfig.me/ip";
    interval = "10min";
  };
}
