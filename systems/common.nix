{
  config,
  inputs,
  pkgs,
  ...
}: {
  networking.networkmanager.enable = true;

  services.gvfs.enable = true;

  programs.nh = {
    enable = true;
    flake = "/home/repparw/nix";
    clean = {
      enable = true;
      extraArgs = "--keep 3 --keep-since 7d";
    };
  };

  users.users.repparw = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF3x0wWO/hQmfN3U8x0OxVqKJ7/nQDWcfg3GkyYKKOkf u0_a452@localhost #termux"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR t440"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH ubritos@gmail.com #alpha"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDWoVcpGRe7JDzWKFEYlYlHdm3es5vsRS0TjXF7uWkvVqU+ZCJhL5K8uQfPnpooht2uOmVo++b2I3w8Ue/v9J7EQ7JTcS0qEq/V9cgV9T+D/6pEwV60V1JHuBeJcVNv5raTk7OH3T5ZIX4IXpcptBGKqH2BOnYTw4I0uSS0JDBs6K/272DsECjq9qNJgQ5avsTvBIaFbrsXi2dIbG9TTgblLZM0PSG4dfQOYspdgWHg6YAJVs3AXnaK+ZrQGD+QH/uGW41muy11MHXBIPqRtLb0cruSGr6dOLLykMu5s6iqg4Xs41igd/j2k3R+X6TI6prNLiioWGzD0ROVbGzxrmnL+SBKFtgO9hj8gkeLOYC4IfSFmjU6tvKho5W4gHNtCb+dK9jL+jo8REJ9LBXzPB4rIb4IlbgvMGDs89HCNkXH7GXyMxprDd0lNGlwcMP/qE7ReUVjqSCHoiIXtZgFzm8Z8rG2oFwucVn7jYypWERrTHao/Me795IouwuY6hKby1U= deck@steamdeck # change to ed25519?"
    ];
    shell = pkgs.zsh;
    description = "repparw";
    extraGroups = [
      "adbusers"
      "networkmanager"
      "wheel"
      "docker"
    ];
  };

  programs.adb.enable = true;

  programs.localsend.enable = true;

  nix.nixPath = ["nixpkgs=${inputs.nixpkgs}"];

  age.secrets = {
    github = {
      file = ../secrets/github.age;
    };
    diun-ntfy = {
      file = ../secrets/diun-ntfy.age;
    };
  };

  nix.settings = {
    access-tokens = config.age.secrets.github.path;
    trusted-users = [
      "root"
      "repparw"
    ];

    substituters = [
      "https://nix-community.cachix.org"
    ];

    trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  nix.optimise.automatic = true;

  nixpkgs.config.allowUnfree = true;

  hardware.keyboard.qmk.enable = true;
}
