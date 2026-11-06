{ den, ... }:
{
  den.aspects.cachix-push.nixos =
    {
      config,
      pkgs,
      ...
    }:
    let
      socketPath = "/run/cachix-push/daemon.sock";
      # The push only talks to the local daemon socket; the daemon uploads
      # asynchronously. A missing or failing daemon must never fail a build,
      # so every failure is swallowed here.
      hookScript = pkgs.writeShellScript "cachix-post-build-hook" ''
        set -f
        export IFS=" "
        if [ -z "''${OUT_PATHS:-}" ]; then
          exit 0
        fi
        # Cachix's upstream filtering already skips paths cache.nixos.org
        # serves. sops vaults additionally never leave the host, even
        # encrypted: they are permanent offline secret material for a public
        # cache.
        filtered="$(printf '%s\n' $OUT_PATHS | grep -vEe '\.sops\.ya?ml$' | xargs)"
        if [ -z "$filtered" ]; then
          exit 0
        fi
        ${pkgs.cachix}/bin/cachix daemon push --socket ${socketPath} $filtered \
          || echo "cachix: daemon push failed with exit $?; continuing." >&2
      '';
    in
    {
      sops.secrets.cachix-push-token = {
        # Host-scoped vault: only this host's age key and the operator key can
        # decrypt it, so revoking one host's token touches no other host.
        sopsFile = ../../secrets/cachix-${config.networking.hostName}.sops.yaml;
        owner = "root";
        group = "root";
        mode = "0400";
        restartUnits = [ "cachix-push-daemon.service" ];
      };

      systemd.services.cachix-push-daemon = {
        description = "Cachix push daemon for repparw.cachix.org";
        after = [
          "network-online.target"
          "sops-nix.service"
        ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Restart = "on-failure";
          RestartSec = "10s";
          RuntimeDirectory = "cachix-push";
          RuntimeDirectoryMode = "0700";
          ExecStart = pkgs.writeShellScript "cachix-push-daemon-start" ''
            export CACHIX_AUTH_TOKEN="$(cat ${config.sops.secrets.cachix-push-token.path})"
            exec ${pkgs.cachix}/bin/cachix daemon run --socket ${socketPath} repparw
          '';
        };
      };

      nix.settings.post-build-hook = "${hookScript}";
    };
}
