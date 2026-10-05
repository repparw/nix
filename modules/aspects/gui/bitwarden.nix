{
  den,
  ...
}:
{
  # Bitwarden Desktop as the shared unlock broker for Firefox and Helium.
  # Each browser extension keeps its own vault session by design; with the
  # desktop app running and browser integration enabled, both extensions
  # unlock via system auth (polkit) instead of separate master-password
  # entries. Upstream already knows Helium's user-data-dir
  # (~/.config/net.imput.helium) and writes its native-messaging manifest
  # there once "Allow browser integration" is toggled in the desktop app,
  # so no manifest files are declared here. That toggle, "Unlock with
  # system authentication" in the desktop app, "Unlock with biometrics" in
  # each extension, and tray-start preferences remain manual one-time steps.
  den.aspects.gui.provides.bitwarden = {
    nixos =
      { pkgs, ... }:
      {
        # System-wide so the polkit action lands in
        # /run/current-system/sw/share/polkit-1/actions, where the polkit
        # daemon looks. A ~/.nix-profile copy would not be found and
        # system-auth unlock would fail to set up.
        environment.systemPackages = [ pkgs.bitwarden-desktop ];

        # The desktop app persists via Electron safeStorage (libsecret),
        # so pin the keyring Niri already defaults on. Note the SDDM PAM
        # service only includes the login stack
        # (security.pam.services.sddm has useDefaultRules = false), so
        # there is no separate SDDM keyring hook to enable. Under SDDM
        # autologin no password is presented, so the login keyring still
        # starts locked; Helium keeps --password-store=basic (see
        # browser.nix) and is unaffected by that locked keyring.
        services.gnome.gnome-keyring.enable = true;
      };

    homeManager =
      { pkgs, ... }:
      {
        # Must stay running: extensions report "desktop app closed" and
        # biometric unlock disappears when it is not.
        systemd.user.services.bitwarden = {
          Unit = {
            Description = "Bitwarden desktop (browser-integration broker)";
            After = [ "graphical-session.target" ];
            PartOf = [ "graphical-session.target" ];
          };
          Service = {
            ExecStart = "${pkgs.bitwarden-desktop}/bin/bitwarden";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
  };
}
