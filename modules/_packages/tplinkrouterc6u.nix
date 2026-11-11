{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  macaddress,
  pycryptodome,
  requests,
  setuptools,
}:

# The Home Assistant integration v2.45.0 requires exactly version 5.38.0.
# Upstream fixed stale smart_network history-only clients in v5.39.0
# (AlexandrErohin/TP-Link-Archer-C6U#260); keep the backported patch until
# the integration accepts the newer client, then use the unpatched package.
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
