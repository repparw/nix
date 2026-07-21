{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  nodejs,
  bash,
}:

stdenvNoCC.mkDerivation {
  pname = "com-addon-node";
  version = "1.0.9";

  src = fetchurl {
    url = "https://github.com/andy-portmen/native-client/releases/download/1.0.9/linux.zip";
    hash = "sha256-s45j9Kf15GA9pa7HsJWIrdL8lQ/Wr/0Bu63Itm6fK/o=";
  };

  nativeBuildInputs = [ unzip ];

  installPhase = ''
        mkdir -p $out/lib/com.add0n.node
        unzip -j $src app/host.js app/messaging.js -d $out/lib/com.add0n.node

        cat > $out/lib/com.add0n.node/run.sh << 'RUNEOF'
    #!${bash}/bin/bash -e
    exec ${lib.getExe nodejs} "$(dirname "$0")/host.js"
    RUNEOF
        chmod +x $out/lib/com.add0n.node/run.sh
  '';

  meta = {
    description = "Native messaging host for the Open In browser extension family";
    homepage = "https://github.com/andy-portmen/native-client";
    license = lib.licenses.mpl20;
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
}
