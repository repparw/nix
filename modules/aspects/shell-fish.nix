{
  den,
  ...
}:
{
  den.aspects.shellFish = {
    includes = [ ];

    homeManager = { pkgs, ... }: {
      programs.fish = {
        enable = true;
      };
    };
  };
}
