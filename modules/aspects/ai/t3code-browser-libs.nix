{ den, ... }:
{
  # T3 downloads chrome-headless-shell at runtime and launches it from the
  # server, so build-time ELF fixups in nixpkgs cannot reach it. nix-ld
  # supplies the interpreter (see t3code.nix), but not this browser's GTK,
  # NSS and GBM libraries. Upstream is adding the library path to the t3code
  # wrappers (NixOS/nixpkgs#575675); until the root pin carries that change,
  # expose the same set system-wide. Completion: delete this file and its
  # include in ai/default.nix (upstream watcher t3code-browser-libs).
  den.aspects.ai.provides.t3code-browser-libs = {
    nixos =
      { pkgs, ... }:
      {
        programs.nix-ld.libraries = with pkgs; [
          alsa-lib
          at-spi2-core
          dbus
          expat
          glib
          libgbm
          libgcc
          libx11
          libxcb
          libxcomposite
          libxdamage
          libxext
          libxfixes
          libxkbcommon
          libxrandr
          nspr
          nss
          systemdLibs
        ];
      };
  };
}
