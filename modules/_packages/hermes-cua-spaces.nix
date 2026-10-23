{ fetchFromGitHub, runCommand }:
let
  source = fetchFromGitHub {
    owner = "trycua";
    repo = "hermes-cua-spaces";
    rev = "82bb8d31517d2d1b8f1ef7f64701558dcac8aea9";
    sha256 = "1c6axxlmf4a8zmw2n2d6p6a0l2l701nsgyb8mnyv02ja720blg64";
  };
in
runCommand "hermes-cua-spaces-0.4.0" { } ''
  mkdir -p $out
  cp -r ${source}/hermes_cua_spaces ${source}/plugin.yaml $out/
  cp ${../aspects/services/hermes-cua/entrypoint.py} $out/__init__.py
''
