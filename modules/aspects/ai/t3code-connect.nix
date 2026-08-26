{
  den,
  ...
}:
{
  # Bake the T3 Connect public identifiers into the package build. The web
  # client gates every cloud feature (sign-in, relay discovery, environment
  # picker) on VITE_* values compiled into its bundle
  # (apps/web/src/cloud/publicConfig.ts hasCloudPublicConfig), so runtime
  # environment on t3code-web.service alone leaves localhost without any
  # T3 Connect UI. Values are the same public (non-secret) identifiers
  # upstream bakes into release builds — see connectEnvironment in ai/t3code.nix.
  den.aspects.ai.provides.t3code-connect = {
    nixos = {
      nixpkgs.overlays = [
        (final: prev: {
          t3code = prev.t3code.override {
            t3code-unwrapped = prev.t3code.unwrapped.overrideAttrs (old: {
              env = (old.env or { }) // {
                T3CODE_CLERK_PUBLISHABLE_KEY = "pk_live_Y2xlcmsudDMuY29kZXMk";
                T3CODE_CLERK_JWT_TEMPLATE = "t3-relay";
                T3CODE_CLERK_CLI_OAUTH_CLIENT_ID = "hzxSgY2cH10sDU2r";
                T3CODE_RELAY_URL = "https://relay.t3.codes";
              };
            });
          };
        })
      ];
    };
  };
}
