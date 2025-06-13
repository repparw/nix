{
  pkgs,
  inputs,
  config,
  ...
}:
{
  imports = [
    ./cli
    ./gui
    ./services
    ./autoUpgrade.nix
    ./style.nix
    ./timers.nix
    ./vm.nix
  ];

  users.users.repparw = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHGd04EwDYl0a0RAS16wbDI4K2cfHFM8guXXYZdH3XtX u0_a426@localhost #termux"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN6UbXeSlW/2jkIU9mQIN5xWElnFbA9tw0BfT072WXgR t440"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH ubritos@gmail.com #alpha"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDWoVcpGRe7JDzWKFEYlYlHdm3es5vsRS0TjXF7uWkvVqU+ZCJhL5K8uQfPnpooht2uOmVo++b2I3w8Ue/v9J7EQ7JTcS0qEq/V9cgV9T+D/6pEwV60V1JHuBeJcVNv5raTk7OH3T5ZIX4IXpcptBGKqH2BOnYTw4I0uSS0JDBs6K/272DsECjq9qNJgQ5avsTvBIaFbrsXi2dIbG9TTgblLZM0PSG4dfQOYspdgWHg6YAJVs3AXnaK+ZrQGD+QH/uGW41muy11MHXBIPqRtLb0cruSGr6dOLLykMu5s6iqg4Xs41igd/j2k3R+X6TI6prNLiioWGzD0ROVbGzxrmnL+SBKFtgO9hj8gkeLOYC4IfSFmjU6tvKho5W4gHNtCb+dK9jL+jo8REJ9LBXzPB4rIb4IlbgvMGDs89HCNkXH7GXyMxprDd0lNGlwcMP/qE7ReUVjqSCHoiIXtZgFzm8Z8rG2oFwucVn7jYypWERrTHao/Me795IouwuY6hKby1U= deck@steamdeck # change to ed25519?"
    ];
    shell = pkgs.fish;
    linger = true;
    initialHashedPassword = "$y$j9T$WPuWlgd7OQOePD8XKqNVv0$Pe9XhFT2hKh1YnyDVHxEwOe.IYTMr8K4JUtxBVjEza/";
    description = "repparw";
    extraGroups = [
      "adbusers"
      "wheel"
    ];
  };

  users.users.root.openssh.authorizedKeys.keys =
    config.users.users.repparw.openssh.authorizedKeys.keys;
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  image.modules.iso-installer = {
    networking.wireless.enable = false;
  };

  networking = {
    networkmanager.enable = true;

    firewall.trustedInterfaces = [
      "enp0s25"
      "enp42s0"
      "wlp3s0"
    ];
  };

  nix = {
    extraOptions = ''
      !include ${config.age.secrets.accessTokens.path}
    '';

    settings = {
      use-xdg-base-directories = true;

      trusted-users = [
        "root"
      ];

      allowed-users = [
        "repparw"
      ];

      experimental-features = "nix-command flakes";
    };

    optimise.automatic = true;
  };

  time.timeZone = "America/Argentina/Buenos_Aires";

  environment.systemPackages = with pkgs; [
    inputs.agenix.packages."${system}".default
  ];

  security = {
    rtkit.enable = true;
    polkit.enable = true;
  };

  hardware = {
    bluetooth = {
      enable = true;
      powerOnBoot = true;
      settings = {
        General = {
          experimental = true; # show battery
          Privacy = "device";
          JustWorksRepairing = "always";
          Class = "0x000100";
          FastConnectable = true;
        };
      };
    };

    keyboard.qmk.enable = true;
  };

  nixpkgs.config.allowUnfree = true;
}
