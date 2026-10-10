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
  util-linux,
  nix-update-script,
}:

stdenv.mkDerivation rec {
  pname = "striptracks";
  version = "unstable-2024-01-01";

  src = fetchFromGitHub {
    owner = "linuxserver";
    repo = "docker-mods";
    rev = "c7db5ea19ad6ba8ada1708f54616c9ea801af5a1";
    hash = "sha256-nkGVyPY/tqgZ4SVc2NC/BGAEukhHxicZP7dJn1wOqb8=";
  };

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  dontUnpack = false;

  installPhase = ''
    mkdir -p $out/bin

    cp root/usr/local/bin/striptracks.sh $out/bin/striptracks.sh
    chmod +x $out/bin/striptracks.sh

    # Keep upstream's executable wrapper (including its shebang), but use the
    # script's :org pseudo-language so Sonarr resolves each series' original
    # language dynamically. Keep the existing English-only subtitle policy.
    cp root/usr/local/bin/striptracks-eng.sh $out/bin/striptracks
    chmod +x $out/bin/striptracks

    substituteInPlace $out/bin/striptracks.sh \
      --replace '/usr/bin/mkvmerge' '${mkvtoolnix}/bin/mkvmerge' \
      --replace '/usr/bin/mkvpropedit' '${mkvtoolnix}/bin/mkvpropedit' \
      --replace '/usr/bin/jq' '${jq}/bin/jq'

    substituteInPlace $out/bin/striptracks \
      --replace '/usr/local/bin/striptracks.sh' "$out/bin/striptracks.sh" \
      --replace '--audio :eng:und --subs :eng' '--audio :eng:org:und --subs :eng'

    wrapProgram $out/bin/striptracks.sh \
      --prefix PATH : ${
        lib.makeBinPath [
          mkvtoolnix
          jq
          curl
          gnused
          gawk
          coreutils
          util-linux
          bash
        ]
      }
  '';

  postFixup = ''
    test -x $out/bin/striptracks
    head -n 1 $out/bin/striptracks | grep -q '^#!'
  '';

  passthru.updateScript = nix-update-script {
    extraArgs = [ "--version=branch=radarr-striptracks" ];
  };

  meta = with lib; {
    description = "Strip unwanted audio and subtitle tracks from video files";
    homepage = "https://github.com/linuxserver/docker-mods/tree/radarr-striptracks";
    license = licenses.gpl3;
    platforms = platforms.linux;
  };
}
