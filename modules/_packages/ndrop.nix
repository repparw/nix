{
  lib,
  stdenv,
  fetchFromGitHub,
  nix-update-script,
  scdoc,
}:

stdenv.mkDerivation rec {
  pname = "ndrop";
  version = "unstable-2024-09-18";

  src = fetchFromGitHub {
    owner = "Schweber";
    repo = "ndrop";
    rev = "f2fb1c611811c48b48cd0f0fecab4f3f935e7405";
    hash = "sha256-/Xco1sr76+F3mAIGq29yp5Y6FPcXS/AVXDpwZ1+rLQk=";
  };

  nativeBuildInputs = [ scdoc ];

  installPhase = ''
    mkdir -p $out/bin
    cp ndrop $out/bin/
    chmod +x $out/bin/ndrop
  '';

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "Run, show and hide programs via keybind in niri (similar to a dropdown terminal)";
    homepage = "https://github.com/Schweber/ndrop";
    license = licenses.agpl3Only;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
