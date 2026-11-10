{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  macaddress,
  pycryptodome,
  requests,
  setuptools,
}:

# Pinned client for the home-assistant TP-Link Router integration with a
# local presence fix: smart_network history-only entries (onlineTime 0) are
# no longer merged into the active-client list. On the Archer AX23 v2 a
# departed phone keeps such an entry, which previously held its tracker at
# "home". Remove the patch when upstream stops merging those entries
# (AlexandrErohin/TP-Link-Archer-C6U#106 tracks the related behavior), then
# switch to the nixpkgs python3Packages package.
buildPythonPackage rec {
  pname = "tplinkrouterc6u";
  version = "5.38.0";

  src = fetchFromGitHub {
    owner = "AlexandrErohin";
    repo = "TP-Link-Archer-C6U";
    tag = "v${version}";
    hash = "sha256-u9njJa1y4qjSuDuOPVSrgS2ZY/01dFl0pIPVz7IB440=";
  };

  patches = [ ./tplink-stale-client.patch ];

  pyproject = true;

  build-system = [ setuptools ];

  dependencies = [
    macaddress
    pycryptodome
    requests
  ];

  # Upstream ships no runnable test suite; the import covers the patched
  # module and the live presence behavior validated the fix.
  pythonImportsCheck = [ "tplinkrouterc6u" ];
  doCheck = false;

  meta = {
    description = "TP-Link Router API client (also supports Mercusys routers)";
    homepage = "https://github.com/AlexandrErohin/TP-Link-Archer-C6U";
    license = lib.licenses.gpl3Plus;
  };
}
