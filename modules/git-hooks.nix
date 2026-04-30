{ inputs, ... }:
{
  imports = [
    (inputs.git-hooks.flakeModule or { })
  ];

  perSystem =
    { config, pkgs, ... }:
    {
      pre-commit = {
        settings = {
          hooks = {
            nixfmt = {
              enable = true;
              package = pkgs.nixfmt;
            };
            deadnix = {
              enable = true;
              args = [
                "--edit"
                "--no-lambda-arg"
                "--no-lambda-pattern-names"
              ];
            };
          };
        };
      };

      devShells.default = pkgs.mkShell {
        nativeBuildInputs = [ config.pre-commit.settings.package ];
        shellHook = config.pre-commit.installationScript;
      };
    };
}
