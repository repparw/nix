{ inputs, ... }:
{
  perSystem =
    { config, pkgs, ... }:
    {
      checks.formatting =
        pkgs.runCommand "check-formatting"
          {
            nativeBuildInputs = [ config.formatter ];
          }
          ''
            export HOME=$(mktemp -d)
            cp -r ${inputs.self} src
            chmod -R +w src
            cd src
            treefmt --tree-root . --walk filesystem --fail-on-change
            touch $out
          '';
    };
}
