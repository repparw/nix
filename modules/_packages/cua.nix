{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  python3Packages,
}:
let
  artifacts = {
    x86_64-linux = {
      url = "https://files.pythonhosted.org/packages/fc/e0/c8cbb5aa2a7302bdb0ef1498dd099e8466919cdb65217215336a730c6e5e/cua-0.7.0-py3-none-manylinux_2_31_x86_64.whl";
      hash = "eefa146dcfcb639f66052b88ca3393a736735bb175e7730327e50398dcdcfc36";
    };
    aarch64-linux = {
      url = "https://files.pythonhosted.org/packages/ee/3a/0cc6d5f0a438edf74bd14e722543a89ba1258ac29042ba682c5ec2f1d65c/cua-0.7.0-py3-none-manylinux_2_31_aarch64.whl";
      hash = "7659d811fac85f419d41d5b61ef56f7a26b131e540c932a24df77884e5144ef2";
    };
  };
  artifact = artifacts.${stdenv.hostPlatform.system};
in
python3Packages.buildPythonPackage {
  pname = "cua";
  version = "0.7.0";
  format = "wheel";
  src = fetchurl {
    inherit (artifact) url;
    sha256 = artifact.hash;
  };
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.cc.lib ];
  pythonImportsCheck = [ "cua" ];
  # The wheel bundles both the UniFFI SDK and the real Rust CLI. Patch both;
  # there is no installer, daemon, VM engine, or local desktop service here.
  postInstall = ''
    chmod +x $out/${python3Packages.python.sitePackages}/cua/bin/cua
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/cua --version | grep -F '0.7.0'
    $out/bin/cua sandbox exec --help | grep -F -- '--stdin'
  '';
  meta = {
    description = "Cua SDK and bundled CLI for remote Spaces";
    homepage = "https://github.com/trycua/cua";
    license = lib.licenses.mit;
    platforms = builtins.attrNames artifacts;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "cua";
  };
}
