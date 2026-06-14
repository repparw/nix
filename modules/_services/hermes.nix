{
  cfg,
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hermesPackage = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  containers.hermes-agent = {
    autoStart = true;
    privateNetwork = true;
    hostAddress = "10.231.136.1";
    localAddress = "10.231.136.11";
    bindMounts = {
      "/projects" = {
        hostPath = "/home/repparw/Projects";
        isReadOnly = false;
      };
    };
    config =
      { ... }:
      {
        imports = [ inputs.hermes-agent.nixosModules.default ];

        services.hermes-agent = {
          enable = true;
          package = hermesPackage;
          addToSystemPackages = true;

          settings = {
            model.default = "anthropic/claude-sonnet-4";
            toolsets = [ "all" ];
            memory = {
              memory_enabled = true;
              user_profile_enabled = true;
            };
            terminal = {
              backend = "local";
              timeout = 180;
            };
          };
        };

        networking.useHostResolvConf = false;
        networking.nameservers = [ "10.231.136.1" ];
        system.stateVersion = "26.05";
      };
  };

  networking.hosts."192.168.0.18" = [
    "hermes.${cfg.domain}"
  ];
}
