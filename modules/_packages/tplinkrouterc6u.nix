{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  macaddress,
  pycryptodome,
  requests,
  setuptools,
}:

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

  pythonImportsCheck = [ "tplinkrouterc6u" ];
  doCheck = false;

  meta = {
    description = "TP-Link Router API client (also supports Mercusys routers)";
    homepage = "https://github.com/AlexandrErohin/TP-Link-Archer-C6U";
    license = lib.licenses.gpl3Plus;
  };
}
