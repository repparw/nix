{ den, ... }:
{
  den.aspects.tasks = {
    includes = [ ];

    homeManager =
      { ... }:
      {
        accounts.calendar = {
          basePath = ".local/share/calendars";
          accounts.nextcloud = {
            remote = {
              type = "caldav";
              url = "https://leo.it.tab.digital/remote.php/dav/calendars/ubritos@gmail.com/";
              userName = "ubritos@gmail.com";
              passwordCommand = [
                "cat"
                "/run/secrets/nextcloud"
              ];
            };
            vdirsyncer = {
              enable = true;
              collections = [ "from a" ];
            };
          };
        };

        programs.vdirsyncer.enable = true;

        services.vdirsyncer = {
          enable = true;
          frequency = "*:0/5";
        };

        programs.todoman = {
          enable = true;
          glob = "*/*";
          extraConfig = ''
            default_list = "Personal"
            default_due = 48
          '';
        };
      };
  };
}
