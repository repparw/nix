{ lib, ... }:
let
  inherit (lib) types mkOption;
in
{
  options.modules.services.inventory = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          hostname = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          title = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          containerAddress = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          port = mkOption {
            type = types.nullOr types.port;
            default = null;
          };
          auth = mkOption {
            type = types.enum [
              "bypass"
              "one_factor"
              "two_factor"
              "external"
            ];
            default = "one_factor";
          };
          backup = mkOption {
            type = types.nullOr (
              types.submodule {
                options = {
                  path = mkOption { type = types.str; };
                };
              }
            );
            default = null;
          };
          monitor = mkOption {
            type = types.bool;
            default = false;
          };
        };
      }
    );
    default = { };
  };
}
