let
  repparw-alpha = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMjQf2hK5Ir0hhdx2VYj6EXU/ZmSHMPZ5u5VzCM77LKa ubritos@gmail.com";
  repparw-beta = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR";
  users = [
    repparw-alpha
    repparw-beta
  ];
in {
  "github.age".publicKeys = users;

  "diun-ntfy.age".publicKeys = users;
}
