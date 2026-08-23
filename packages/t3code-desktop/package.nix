# Local stopgap mirroring pkgs/by-name/t3/t3code-desktop/package.nix from
# NixOS/nixpkgs#555814 until it merges and reaches our pin. Linux-only: no
# host in this repo runs Darwin, so the .app bundle packaging is omitted.
{
  lib,
  stdenv,
  symlinkJoin,
  makeBinaryWrapper,
  copyDesktopItems,
  makeDesktopItem,
  electron_41,
  enableCodex ? true,
  codex,
  enableGitHub ? true,
  gh,
  enableGit ? true,
  git,
  enableResourceMonitor ? true,
  t3code,
}:

let
  t3code-unwrapped = t3code.unwrapped;

  # Kept in lockstep with the defaults of the `t3code` join so both wrappers
  # spawn backends with the same environment.
  runtimePackages =
    lib.optionals enableCodex [ codex ]
    ++ lib.optionals enableGitHub [ gh ]
    ++ lib.optionals enableGit [ git ];

  wrapperArgs =
    lib.optionals (runtimePackages != [ ]) [
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath runtimePackages)
    ]
    ++ lib.optionals enableResourceMonitor [
      "--set-default"
      "T3CODE_RESOURCE_MONITOR_PATH"
      (lib.getExe t3code.resourceMonitor)
    ];

in
symlinkJoin {
  pname = "t3code-desktop";
  inherit (t3code-unwrapped) version;
  __structuredAttrs = true;
  strictDeps = true;

  paths = [ t3code-unwrapped ];

  nativeBuildInputs = [
    copyDesktopItems
    makeBinaryWrapper
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "t3code";
      desktopName = "T3 Code (Alpha)";
      comment = "Minimal web GUI for coding agents";
      exec = "t3code-desktop %U";
      terminal = false;
      icon = "t3code";
      startupWMClass = "t3code";
      categories = [ "Development" ];
    })
  ];

  postBuild = ''
    # Electron is owned by this package alone, so headless users of `t3code`
    # do not pull the Electron/GTK/GStreamer stack into their closure.
    makeWrapper ${lib.getExe electron_41} "$out/bin/t3code-desktop" \
      --add-flags "$out/libexec/t3code/apps/desktop" \
      --inherit-argv0 ${lib.escapeShellArgs wrapperArgs}

    mkdir --parents "$out"/share/icons/hicolor/scalable/apps
    install --mode=444 ${"${t3code-unwrapped.src}/assets/prod/black-universal-1024.png"} "$out"/share/icons/t3code.png
    install --mode=444 ${t3code-unwrapped.src}/assets/prod/logo.svg \
      "$out"/share/icons/hicolor/scalable/apps/t3code.svg
  '';

  meta = {
    description = "Minimal web GUI for coding agents (Electron desktop app)";
    # Manually inherit so that pos works
    inherit (t3code-unwrapped.meta)
      homepage
      downloadPage
      changelog
      license
      maintainers
      platforms
      ;
    mainProgram = "t3code-desktop";
  };
}
