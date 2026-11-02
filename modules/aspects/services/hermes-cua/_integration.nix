{
  lib,
  source,
  ref,
  runtime,
}:
let
  # The compatibility contract is the pinned provider source itself: a
  # reviewed release tag whose terminal_env_provider exposes the stream APIs
  # the CUA backend needs. The former v0.22.3 version floor was retired once
  # the hermes-update stable tracker kept the pin at a current release; a
  # source without the markers — old, new, or a moved main — still fails.
  release = builtins.match "v[0-9]+\\.[0-9]+\\.[0-9]+" ref;
  provider = builtins.readFile (source + "/agent/terminal_env_provider.py");
  supported =
    release != null && lib.hasInfix "supports_streams" provider && lib.hasInfix "default_cwd" provider;
  ready =
    supported && lib.versionAtLeast runtime.version "0.7.0" && lib.versionOlder runtime.version "0.8";
in
{
  inherit supported ready;
  settings = lib.optionalAttrs ready {
    terminal.backend = "cua";
    plugins.entries.cua-spaces = {
      enabled = true;
      settings = {
        # Enrollment must register this existing remote Linux Space. A missing
        # name fails; it never enters the plugin's approval-bypassing create mode.
        space = "hermes-gui";
        desktop = false;
        delete_on_exit = false;
      };
    };
  };
}
