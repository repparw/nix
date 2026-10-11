{ den, ... }:
{
  # Retire after stable orchestrator v2 reaches the root Nixpkgs pin (#209).
  den.aspects.ai.provides.t3code-nightly = {
    nixos = {
      nixpkgs.overlays = [
        (final: prev: {
          t3code-nightly = prev.stdenv.mkDerivation rec {
            pname = "t3code-server";
            version = "0.0.46-nightly.20261011.2980";
            src = prev.fetchurl {
              url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/t3-${version}-linux-x64.tar.gz";
              hash = "sha256-qaD00i7kZNoR3DId1diTOCQg6RLE/aT9MS2Ok1XVkXs=";
            };
            nativeBuildInputs = with prev; [
              autoPatchelfHook
              installShellFiles
              makeBinaryWrapper
            ];
            buildInputs = [ prev.stdenv.cc.cc.lib ];
            dontStrip = true;
            installPhase = ''
              runHook preInstall

              mkdir -p $out/libexec
              cp -rT . $out/libexec/t3code
              makeWrapper $out/libexec/t3code/t3 $out/bin/t3 \
                --prefix PATH : "${
                  prev.lib.makeBinPath [
                    prev.git
                    prev.gh
                    prev.codex
                  ]
                }"

              runHook postInstall
            '';
            postFixup = ''
              for shell in bash fish zsh; do
                if "$out/bin/t3" --completions "$shell" > ".t3-completions.$shell" 2>/dev/null \
                  && [ -s ".t3-completions.$shell" ]; then
                  installShellCompletion --cmd t3 --"$shell" ".t3-completions.$shell"
                fi
              done
            '';
            meta = {
              description = "Pinned T3 Code orchestrator v2 nightly server";
              homepage = "https://github.com/pingdotgg/t3code";
              license = prev.lib.licenses.mit;
              mainProgram = "t3";
              platforms = [ "x86_64-linux" ];
              sourceProvenance = [ prev.lib.sourceTypes.binaryNativeCode ];
            };
          };
        })
      ];
    };
    homeManager = { lib, pkgs, ... }: {
      systemd.user.services.t3code-web.Service.ExecStart =
        lib.mkForce "${pkgs.t3code-nightly}/bin/t3 serve --mode web";
    };
  };
}
