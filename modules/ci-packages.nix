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
  # Aspects whose services don't expose enable/package options are invisible
  # to the collector above. List them explicitly so main-packages pushes them
  # and pi deploys substitute instead of building the node stacks on target
  # (#521). The epicgames-freegames-node package arrives with the #542 trial
  # PR and joins this list there. The _tests/ci-packages.nix harness uses
  # a lightweight callPackage stub to verify these paths without real builds.
  explicitPackages =
    system:
    lib.optionals ((inputs ? nixpkgs) && system == "aarch64-linux") (
      let
        pkgs = inputs.nixpkgs.legacyPackages.${system};
      in
      [
        (pkgs.callPackage ./_packages/free-games-claimer.nix { })
      ]
    );
  targetsFor =
    system:
    lib.listToAttrs (
      lib.imap0
        (index: package: {
          name = "package-${toString index}";
          value = package;
        })
        (
          (lib.concatMap (host: packagesFor host.config host.options.services) (
            lib.filter (host: host.config.nixpkgs.hostPlatform.system == system) hosts
          ))
          ++ (explicitPackages system)
        )
    );
in
{
  flake.ciPackages = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] targetsFor;

  flake.ciPackageSmoke = lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (
    system:
    let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      revision = builtins.substring 0 12 (inputs.self.rev or "unversioned");
    in
    {
      smoke = pkgs.runCommand "main-package-smoke-${revision}" { } ''
        printf '%s\\n' '${system}' > "$out"
      '';
    }
  );
  perSystem = { pkgs, ... }: {
    packages.nix-fast-build = pkgs.nix-fast-build;
    checks.ci-package-targets = import ./_tests/ci-packages.nix { inherit pkgs; };
  };
}
