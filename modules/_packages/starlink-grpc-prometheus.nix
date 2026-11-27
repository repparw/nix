{
  lib,
  python3,
  python3Packages,
  fetchurl,
  stdenvNoCC,
  makeWrapper,
}:
let
  version = "1.3.0";
  upstream = "https://raw.githubusercontent.com/sparky8512/starlink-grpc-tools/v${version}";
in
# nixpkgs' python3Packages.starlink-grpc-core builds only the library from the
# upstream packaging/ subproject (starlink_grpc, plus grpcio/protobuf/yagrc
# dependencies), so the Prometheus front end has to come from the same source.
# The two script files are not published to PyPI; pin them from the matching
# upstream tag so script and library behavior cannot drift apart.
stdenvNoCC.mkDerivation {
  pname = "starlink-grpc-prometheus";
  inherit version;

  nativeBuildInputs = [ makeWrapper ];

  dontUnpack = true;

  buildCommand = ''
    mkdir -p "$out/lib" "$out/bin"
    install -m 0444 ${
      fetchurl {
        url = "${upstream}/dish_grpc_prometheus.py";
        hash = "sha256-nMRZQVQaeCRoxQDx22gW87tPQM57Y1CCyTJ/DftJpw8=";
      }
    } "$out/lib/dish_grpc_prometheus.py"
    install -m 0444 ${
      fetchurl {
        url = "${upstream}/dish_common.py";
        hash = "sha256-0dOA5oUhCKRmnXNKMHmeVoy3GFgwlQLNwW4+1U8RSf8=";
      }
    } "$out/lib/dish_common.py"
    makeWrapper "${python3.withPackages (ps: [ ps.starlink-grpc-core ])}/bin/python3" \
      "$out/bin/starlink-grpc-prometheus" \
      --add-flags "$out/lib/dish_grpc_prometheus.py"
  '';

  # Run as: starlink-grpc-prometheus [--target DISH:PORT] [--samples N]
  #   status alert_detail ping_drop usage power
  # Every request it makes to the dish (get_status, get_history) is read-only.

  meta = {
    description = "Prometheus exporter for Starlink user terminal gRPC data";
    homepage = "https://github.com/sparky8512/starlink-grpc-tools";
    license = lib.licenses.unlicense;
    mainProgram = "starlink-grpc-prometheus";
  };
}
