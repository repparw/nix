{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  mkvtoolnix,
  bash,
  jq,
  curl,
  gnused,
  gawk,
  coreutils,
  nix-update-script,
}:

stdenv.mkDerivation rec {
  pname = "striptracks";
  version = "unstable-2024-01-01";

  src = fetchFromGitHub {
    owner = "linuxserver";
    repo = "docker-mods";
    rev = "radarr-striptracks";
    hash = "sha256-nkGVyPY/tqgZ4SVc2NC/BGAEukhHxicZP7dJn1wOqb8=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  dontUnpack = false;

  installPhase = ''
    mkdir -p $out/bin

    cp root/usr/local/bin/striptracks.sh $out/bin/striptracks.sh
    chmod +x $out/bin/striptracks.sh

    cp root/usr/local/bin/striptracks-eng.sh $out/bin/striptracks
    chmod +x $out/bin/striptracks

    substituteInPlace $out/bin/striptracks.sh \
      --replace '/usr/bin/mkvmerge' '${mkvtoolnix}/bin/mkvmerge' \
      --replace '/usr/bin/mkvpropedit' '${mkvtoolnix}/bin/mkvpropedit' \
      --replace '/usr/bin/jq' '${jq}/bin/jq'

    substituteInPlace $out/bin/striptracks \
      --replace '/usr/local/bin/striptracks.sh' "$out/bin/striptracks.sh"

    wrapProgram $out/bin/striptracks.sh \
      --prefix PATH : ${
        lib.makeBinPath [
          mkvtoolnix
          jq
          curl
          gnused
          gawk
          coreutils
          bash
        ]
      }
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch" ];
  };

  meta = with lib; {
    description = "Strip unwanted audio and subtitle tracks from video files";
    homepage = "https://github.com/linuxserver/docker-mods/tree/radarr-striptracks";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
