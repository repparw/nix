let
  repparw-alpha = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH";
  repparw-beta = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR";
  users = [
    repparw-alpha
    repparw-beta
  ];

  alpha = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIrytCarAMw1Q2QfgBQd1jgtWsLdetbFXepFEcxwKOBI";
  systems = [
    alpha
  ];
in
{
  "github.age".publicKeys = [
    repparw-alpha
    repparw-beta
    alpha
  ];
}
