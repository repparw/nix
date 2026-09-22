{ den, ... }:
{
  # Stopgap for nixpkgs#555814 (split t3code into t3code-desktop and
  # t3code-cli): headless hosts need only `t3 serve`, but overrideAttrs on
  # unwrapped busts the binary cache and the full rebuild needs gigabytes of
  # scratch that pi's 40G /nix cannot spare. Copy the prebuilt server tree
  # out of the substituted binary instead: no Electron, no desktop launcher,
  # no local pnpm build. Completion: git rm this file, pin
  # programs.t3code.package to pkgs.t3code-cli on pi (see watch-t3code-split).
  den.aspects.ai.provides.t3code-split = {
    nixos = {
      nixpkgs.overlays = [
        (final: prev: {
          t3code-server = prev.stdenv.mkDerivation {
            pname = "t3code-server";
            inherit (prev.t3code.unwrapped) version;
            dontUnpack = true;
            # The server tree must not reference the full bundle (that would
            # drag Electron and the desktop tree back into the closure).
            disallowedRequisites = [ prev.t3code.unwrapped ];
            nativeBuildInputs = with prev; [
              installShellFiles
              makeBinaryWrapper
            ];
            meta = {
              description = "T3 Code server without the Electron desktop app";
              mainProgram = "t3";
            };
            installPhase = ''
              runHook preInstall

              mkdir -p $out/bin
              cp --recursive --no-preserve=mode ${prev.t3code.unwrapped}/libexec $out/libexec
              rm -rf $out/libexec/t3code/apps/desktop
              find $out/libexec/t3code -xtype l -delete
              makeWrapper ${prev.lib.getExe prev.nodejs} $out/bin/t3 \
                --add-flags "$out/libexec/t3code/apps/server/dist/bin.mjs" \
                --prefix PATH : "${
                  prev.lib.makeBinPath [
                    prev.codex
                    prev.gh
                    prev.git
                  ]
                }"

              runHook postInstall
            '';
            postInstall = prev.lib.optionalString (prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform) ''
              for shell in bash fish zsh; do
                installShellCompletion --cmd t3 --"$shell" <("$out/bin/t3" --completions "$shell")
              done
            '';
          };
        })
      ];
    };

    homeManager =
      { pkgs, ... }:
      {
        programs.t3code.package = pkgs.t3code-server;
      };
  };
}
