{
  den,
  ...
}:
{
  den.aspects.logid = {
    includes = [ ];

    nixos = {
      services.logiops = {
        enable = true;
        config = {
          devices = [
            {
              name = "MX Vertical Advanced Ergonomic Mouse";
              smartshift = {
                on = true;
                threshold = 30;
              };
              hiresscroll = {
                hires = true;
                invert = false;
                target = false;
              };
              dpi = 1600;
              buttons = [
                {
                  cid = 253;
                  action = {
                    type = "Keypress";
                    keys = [
                      "KEY_LEFTSHIFT"
                      "KEY_LEFTMETA"
                      "KEY_PRINT"
                    ];
                  };
                }
              ];
            }
          ];
        };
      };
    };
  };
}
