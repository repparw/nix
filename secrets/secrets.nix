let
  repparw-alpha = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH";
  repparw-beta = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR";
  users = [
    repparw-alpha
    repparw-beta
  ];
in
{
  "access-tokens.age".publicKeys = users;

  "services/rclone/crypt.age".publicKeys = users;
  "services/rclone/drive-token.age".publicKeys = users;
  "services/rclone/drive-secret.age".publicKeys = users;
  "services/rclone/drive-id.age".publicKeys = users;
  "services/rclone/dropbox.age".publicKeys = users;

  "tod0.age".publicKeys = users;

  "services/freshrss.age".publicKeys = users;

  "steam-password.age".publicKeys = users;
}
