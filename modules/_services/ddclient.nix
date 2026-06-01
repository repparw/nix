{
  config,
  ...
}:
{
  services.ddclient = {
    enable = true;
    protocol = "cloudflare";
    zone = "repparw.com";
    domains = [ "repparw.com" ];
    username = "token";
    passwordFile = config.sops.secrets.cloudflare.path;
    usev4 = "web, web=ifconfig.me/ip";
    interval = "10min";
  };
}
