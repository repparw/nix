{
  lib,
  source,
  ref,
  runtime,
}:
let
  release = builtins.match "v([0-9]+\\.[0-9]+\\.[0-9]+)" ref;
  version = if release == null then null else builtins.head release;
  provider = builtins.readFile (source + "/agent/terminal_env_provider.py");
  supported =
    version != null
    && lib.versionAtLeast version "0.22.3"
    && lib.hasInfix "supports_streams" provider
    && lib.hasInfix "default_cwd" provider;
  ready =
    supported && lib.versionAtLeast runtime.version "0.7.0" && lib.versionOlder runtime.version "0.8";
in
{
  inherit version supported ready;
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
