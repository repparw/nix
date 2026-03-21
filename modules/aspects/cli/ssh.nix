{
  den,
  ...
}:
{
  den.aspects.ssh = {
    includes = [ ];

    homeManager =
      { ... }:
      {
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;

          matchBlocks = {
            pi = {
              hostname = "192.168.0.4";
              user = "repparw";
            };
          };
        };
      };
  };
}
