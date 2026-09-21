_: {
  perSystem =
    { pkgs, ... }:
    {
      formatter = pkgs.treefmt.withConfig {
        runtimeInputs = with pkgs; [
          nixfmt
          deadnix
          prettier
        ];
        settings = {
          on-unmatched = "info";
          formatter.nixfmt = {
            command = "nixfmt";
            includes = [ "*.nix" ];
          };
          formatter.deadnix = {
            command = "deadnix";
            options = [
              "--edit"
              "--no-lambda-arg"
              "--no-lambda-pattern-names"
            ];
            includes = [ "*.nix" ];
          };
          formatter.prettier = {
            command = "prettier";
            options = [ "--write" ];
            includes = [ "*.md" ];
          };
        };
      };
    };
}
