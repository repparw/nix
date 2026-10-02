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

    # Upstream also ships striptracks-eng.sh, a one-line wrapper that hardcodes
    # `--audio :eng:und --subs :eng`. Shipping that strips the original audio
    # track from every release that is not originally English: an anime with
    # jpn + eng loses its jpn track and keeps the dub. mkv carries no
    # "original" tag, only concrete ISO 639 codes, so keeping the original
    # means keeping the languages that are original somewhere in the library.
    # Keep undetermined too, for tracks the release never tagged.
    #
    # Re-derive this list when the library gains a series in a new original
    # language:
    #   curl -s -H "X-Api-Key: $KEY" \
    #     http://SONARR:8989/api/v3/series \
    #     | jq -r 'group_by(.originalLanguage.name)[]
    #              | "\(.[0].originalLanguage.name)\t\(length)"'
    keep_audio=":und:eng:jpn:spa:chi:ita:ger"
    keep_subs=":und:eng:jpn:spa:chi:ita:ger"
    cat > $out/bin/striptracks <<EOF
    . $out/bin/striptracks.sh --audio $keep_audio --subs $keep_subs
    EOF
    chmod +x $out/bin/striptracks

    substituteInPlace $out/bin/striptracks.sh \
      --replace '/usr/bin/mkvmerge' '${mkvtoolnix}/bin/mkvmerge' \
      --replace '/usr/bin/mkvpropedit' '${mkvtoolnix}/bin/mkvpropedit' \
      --replace '/usr/bin/jq' '${jq}/bin/jq'

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
