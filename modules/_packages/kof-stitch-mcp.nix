{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  google-cloud-sdk,
  coreutils,
}:

buildNpmPackage {
  pname = "kof-stitch-mcp";
  version = "1.3.0";

  src = fetchFromGitHub {
    owner = "keeponfirst";
    repo = "kof-stitch-mcp";
    rev = "bcbb421df59a9dc6cc287c5a91e2d27d487a9876";
    hash = "sha256-aTrY12tTek76FEnZrfgGYG4vJwuWgSD2pbiUai0SvZE=";
  };

  npmDepsHash = "sha256-HyqYRQ46DVyd/jcyodWDmtU9DmYSBuaIdFthO3U1jck=";
  dontNpmBuild = true;
  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/kof-stitch-mcp \
      --prefix PATH : ${
        lib.makeBinPath [
          google-cloud-sdk
          coreutils
        ]
      }
  '';

  meta = {
    description = "Stdio MCP server for Google Stitch with Google Cloud authentication";
    homepage = "https://github.com/keeponfirst/kof-stitch-mcp";
    license = lib.licenses.mit;
    mainProgram = "kof-stitch-mcp";
  };
}
