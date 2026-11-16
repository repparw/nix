{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  macaddress,
  pycryptodome,
  requests,
  setuptools,
}:

# Custom package for the home-assistant TP-Link Router integration. The
# package is not available in the pinned nixpkgs, while the integration's
# manifest requires this exact client release.
buildPythonPackage rec {
  pname = "tplinkrouterc6u";
  version = "5.40.0";

  src = fetchFromGitHub {
    owner = "AlexandrErohin";
    repo = "TP-Link-Archer-C6U";
    tag = "v${version}";
    hash = "sha256-VSz8aV3kZ7QpCUkFZgogGWxfyd4kUduFzQf7rlL9yC8=";
  };

  pyproject = true;

  build-system = [ setuptools ];

  dependencies = [
    macaddress
    pycryptodome
    requests
  ];

  # Upstream ships no runnable test suite; the import covers the client
  # module while integration behavior is validated at runtime.
  pythonImportsCheck = [ "tplinkrouterc6u" ];
  doCheck = false;

  meta = {
    description = "TP-Link Router API client (also supports Mercusys routers)";
    homepage = "https://github.com/AlexandrErohin/TP-Link-Archer-C6U";
    license = lib.licenses.gpl3Plus;
  };
}
