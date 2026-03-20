{
  den,
  lib,
  ...
}:
{
  den.aspects.mpv = {
    includes = [ ];

    homeManager =
      { ... }:
      {
        programs.mpv = {
          enable = true;
          bindings = {
            WHEEL_UP = "add volume 2";
            WHEEL_DOWN = "add volume -2";
            "," = "seek -5";
            "." = "seek 5";
            LEFT = "frame-back-step";
            RIGHT = "frame-step";
          };
          config = {
            volume = 50;
            hwdec = "vaapi";
            vo = "gpu-next";
            gpu-api = "vulkan";
            screenshot-directory = "~/Pictures/mpvss";
            osd-level = 0;
            sub-auto = "fuzzy";
            slang = "eng,en";
            alang = "eng,en";
            autofit-larger = "90%";
          };
        };
      };
  };
}
