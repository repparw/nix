{ den, ... }:
{
  den.aspects.zellij = {
    includes = [ ];

    homeManager =
      { ... }:
      {
        programs.zellij = {
          enable = true;
          settings = {
            scroll_buffer_size = 10000;
            mouse_mode = true;
            session_serialization = true;
            serialize_pane_viewport = true;
            scrollback_lines_to_serialize = 10000;
            show_startup_tips = false;
            show_release_notes = false;
          };
        };
      };
  };
}
