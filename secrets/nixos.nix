{
  lib,
  config,
  inputs,
  ...
}:
{
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  sops.defaultSopsFile = ./secrets.yaml;
  sops.defaultSopsFormat = "yaml";

  sops.age.sshKeyPaths = [ "/home/repparw/.ssh/id_ed25519" ];

  sops.secrets = {
    accessTokens = {
      mode = "0440";
      owner = "repparw";
    };
    nextcloud = {
      owner = "repparw";
    };
  }
  // (lib.optionalAttrs config.modules.timers.enable {
    rcloneDriveToken = {
      owner = "repparw";
    };
    rcloneDriveId = {
      owner = "repparw";
    };
    rcloneDriveSecret = {
      owner = "repparw";
    };
    rcloneCrypt = {
      owner = "repparw";
    };
    rcloneDropbox = {
      owner = "repparw";
    };
    rcloneNextcloud = {
      owner = "repparw";
    };
  })
  // (lib.optionalAttrs config.services.archisteamfarm.enable {
    steamPassword = {
      owner = "archisteamfarm";
    };
  })
  // (lib.optionalAttrs config.modules.services.enable {
    freshrss = { };
    cloudflare = { };
  });

  sops.templates."cfait-config.toml" = {
    content = ''
      url = "https://leo.it.tab.digital/remote.php/dav/"
      username = "ubritos@gmail.com"
      password = "${config.sops.placeholder.nextcloud}"
      default_calendar = "Personal"
      disabled_calendars = ["local://default"]
    '';
    owner = "repparw";
    path = "/home/repparw/.config/cfait/config.toml";
  };
}
