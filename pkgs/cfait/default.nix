{
  lib,
  rustPlatform,
  fetchFromGitHub,
  openssl,
  sqlite,
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

  buildInputs = [
    openssl
    sqlite
  ];

  cargoBuildFlags = [
    "--bin"
    "cfait"
  ];

  doCheck = false;

  meta = {
    description = "A powerful, fast and elegant task manager (CalDAV and local, CLI and TUI)";
    homepage = "https://codeberg.org/trougnouf/cfait";
    license = lib.licenses.gpl3Only;
    maintainers = [ ];
    mainProgram = "cfait";
  };
}
