{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  sqlite,
  libxkbcommon,
  wayland,
  libx11,
  libxcursor,
  libxrandr,
  libxi,
  makeWrapper,
}:

rustPlatform.buildRustPackage rec {
  pname = "cfait";
  version = "0.4.9";

  src = fetchFromGitHub {
    owner = "trougnouf";
    repo = "cfait";
    rev = "v${version}";
    hash = "sha256-7cbJ5HEkGhjIOnIeBEasa5TVurXcSLuOB3rOMLFd+os=";
  };

  cargoHash = "sha256-2P9ybgIIvG7oaVOkvPaWNYyIMfa9PFlJbnLaGe4IYjc=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];

  buildInputs = [
    openssl
    sqlite
    libxkbcommon
    wayland
    libx11
    libxcursor
    libxrandr
    libxi
  ];

  buildFeatures = [ "gui" ];

  cargoBuildFlags = [
    "--bin"
    "cfait"
    "--bin"
    "gui"
  ];

  postInstall = ''
    mv $out/bin/gui $out/bin/cfait-gui
  '';

  postFixup = ''
    wrapProgram $out/bin/cfait-gui \
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          libxkbcommon
          wayland
          libx11
          libxcursor
          libxrandr
          libxi
        ]
      }"
  '';

  doCheck = false;

  meta = {
    description = "A powerful, fast and elegant task manager (CalDAV and local, GUI, TUI, and Android clients)";
    homepage = "https://codeberg.org/trougnouf/cfait";
    license = lib.licenses.gpl3Only;
    maintainers = [ ];
    mainProgram = "cfait";
  };
}
