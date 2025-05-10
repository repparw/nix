let
  repparw-alpha = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH";
  repparw-beta = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR";
  users = [
    repparw-alpha
    repparw-beta
  ];
in {
  "access-tokens.age".publicKeys = users;

  "rclone-crypt.age".publicKeys = users;
  "rclone-drive.age".publicKeys = users;
  "rclone-dropbox.age".publicKeys = users;

  "tod0.age".publicKeys = users;
}
