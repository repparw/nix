{ inputs, lib, ... }:
{
  perSystem =
    { system, ... }:
    {
      # Select the installed, Stylix-extended package from the real host, without
      # the package stubs used by checks.alpha. Building it forces its closure.
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        host-neovim =
          lib.findSingle (package: package.meta.mainProgram or "" == "nvim")
            (throw "alpha must install a Neovim package")
            (throw "alpha must install exactly one Neovim package")
            inputs.self.nixosConfigurations.alpha.config.home-manager.users.repparw.home.packages;
      };
    };
}
