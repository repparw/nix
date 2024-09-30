{ ... }:
{
  services.waybar = {
    enable = true;
    config = {
      position = "top";
      modules = [
        {
          type = "custom/text";
          exec = "echo 'Hello, World!'";
        }
      ];
    };
  };
}
