{ inputs, lib, ... }:
let
  packagesFor =
    config: serviceOptions:
    config.environment.systemPackages
    ++ lib.concatMap (user: user.home.packages) (lib.attrValues (config.home-manager.users or { }))
    ++
      lib.concatMap
        (
          name:
          let
            service = config.services.${name} or { };
          in
          lib.optional (
            (service.enable or false) && lib.isDerivation (service.package or null)
          ) service.package
        )
        (
          lib.attrNames (
            lib.filterAttrs (
              _: option:
              option ? enable
              && option ? package
              && (option.enable.visible or true)
              && (option.package.visible or true)
            ) serviceOptions
          )
        )
    ++ lib.concatMap (container: packagesFor container.config serviceOptions) (
      lib.attrValues config.containers
    );
  hosts = map (host: inputs.self.nixosConfigurations.${host}) [
    "alpha"
    "pi"
    "epsilon"
  ];
  targetsFor =
    system:
    lib.listToAttrs (
      lib.imap0
        (index: package: {
          name = "package-${toString index}";
          value = package;
        })
        (
          lib.concatMap (host: packagesFor host.config host.options.services) (
            lib.filter (host: host.config.nixpkgs.hostPlatform.system == system) hosts
          )
        )
    );
in
{
  # Individual package targets let nix-fast-build skip cached results without
  # realizing system paths, activation scripts, or host toplevels.
  flake.ciPackages = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] targetsFor;
  perSystem = { pkgs, ... }: {
    packages.nix-fast-build = pkgs.nix-fast-build;
    checks.ci-package-targets = import ./_tests/ci-packages.nix { inherit pkgs; };
  };
}
