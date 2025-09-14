let
  users = import ../modules/nixos/keys.nix;
in
{
  "access-tokens.age".publicKeys = users;

  "services/rclone/crypt.age".publicKeys = users;
  "services/rclone/drive-token.age".publicKeys = users;
  "services/rclone/drive-secret.age".publicKeys = users;
  "services/rclone/drive-id.age".publicKeys = users;
  "services/rclone/dropbox.age".publicKeys = users;
  "services/rclone/nextcloud.age".publicKeys = users;

  "nextcloud.age".publicKeys = users;

  "services/proxy/cloudflare.age".publicKeys = users;

  "services/freshrss.age".publicKeys = users;

  "steam-password.age".publicKeys = users;
}
