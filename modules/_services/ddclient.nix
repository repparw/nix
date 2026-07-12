{
  config,
  lib,
  ...
}:
{
  sops.secrets.ddclientPassword = {
    sopsFile = ../../secrets/ddclient.yaml;
    owner = "ddclient";
    group = "ddclient";
    mode = "0400";
  };

  users.users.ddclient = {
    isSystemUser = true;
    group = "ddclient";
  };
  users.groups.ddclient = { };

  systemd.services.ddclient.serviceConfig = {
    DynamicUser = lib.mkForce false;
    User = lib.mkForce "ddclient";
  };
  systemd.tmpfiles.rules = [
    "d /var/lib/ddclient 0700 ddclient ddclient -"
  ];

  services.ddclient = {
    enable = true;
    protocol = "cloudflare";
    zone = "repparw.com";
    domains = [ "repparw.com" ];
    username = "token";
    passwordFile = config.sops.secrets.ddclientPassword.path;
    usev4 = "webv4, webv4=ifconfig.me/ip";
    usev6 = "disabled";
    interval = "10min";
  };
}
