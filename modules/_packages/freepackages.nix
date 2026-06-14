{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
}:

stdenvNoCC.mkDerivation rec {
  pname = "freepackages";
  version = "1.6.3.2";

  src = fetchurl {
    url = "https://github.com/Citrinate/FreePackages/releases/download/${version}/FreePackages.zip";
    hash = "sha256-Qw/zKpZintu3P72mnjqwf+tRSnssr3dDpWJGUHmQJxg=";
  };

  sourceRoot = ".";
  nativeBuildInputs = [ unzip ];

  installPhase = ''
    mkdir -p $out/lib/FreePackages
    cp -r . $out/lib/FreePackages/
  '';

  meta = with lib; {
    description = "ASF plugin for finding and redeeming free Steam games";
    homepage = "https://github.com/Citrinate/FreePackages";
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
