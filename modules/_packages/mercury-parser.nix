{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  makeWrapper,
}:

buildNpmPackage rec {
  pname = "mercury-parser-api";
  version = "unstable-2024-01-01";

  src = fetchFromGitHub {
    owner = "cire36";
    repo = "mercury-parser-api";
    rev = "master";
    hash = "sha256-ub5mzXRNL68UlW2/ZM215a+WLY2EgYigjbvZoQpw+1o=";
  };

  postPatch = ''
    cp ${./mercury-parser-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-n8UV+gJ8/F/AJRL6YmchuDuN+wKRLC3HBBX6o2Tq7Qk=";
  makeCacheWritable = true;
  dontNpmBuild = true;

  installPhase = ''
    mkdir -p $out/{bin,lib/mercury-parser-api}
    cp -r node_modules package.json mercury-api-server.js $out/lib/mercury-parser-api/

    makeWrapper ${nodejs}/bin/node $out/bin/mercury-parser-api \
      --add-flags "$out/lib/mercury-parser-api/mercury-api-server.js"
  '';

  meta = with lib; {
    description = "Mercury Parser API server";
    homepage = "https://github.com/cire36/mercury-parser-api";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
