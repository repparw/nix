{ den, ... }:
{
  # Bridging pin for nixpkgs#575132 (t3code 0.0.45 -> 0.1.0): serve stable
  # orchestrator-V2 0.1.0 from the upstream release archive so fleet clients
  # on the stable channel can connect before the root Nixpkgs pin packages
  # 0.1.0. Same prebuilt-archive shape as t3code-nightly.nix: no local
  # pnpm build, no Electron, no desktop tree. Completion: once 0.1.0 (or
  # newer) reaches the root Nixpkgs pin, delete this file and its entity
  # includes; the PR #285 version assertion then owns the retirement gate
  # (issue #209; upstream watcher t3code-stable010).
  den.aspects.ai.provides.t3code-stable010 = {
    nixos = {
      nixpkgs.overlays = [
        (final: prev: {
          t3code-stable010 =
            let
              releases = {
                x86_64-linux = {
                  arch = "x64";
                  hash = "sha256-93A/8buPYkNYAFizzPLAKrti66S5keJrux2iL0tW2bE=";
                };
                aarch64-linux = {
                  arch = "arm64";
                  hash = "sha256-LQd1GpGCUrb6LTgRn+RMUUm2Kk1oSJSvXChT6LKpToE=";
                };
              };
              release = releases.${prev.stdenv.hostPlatform.system};
            in
            prev.stdenv.mkDerivation rec {
              pname = "t3code-server";
              version = "0.1.0";
              src = prev.fetchurl {
                url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/t3-${version}-linux-${release.arch}.tar.gz";
                inherit (release) hash;
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
                description = "Pinned T3 Code stable V2 server";
                homepage = "https://github.com/pingdotgg/t3code";
                license = prev.lib.licenses.mit;
                mainProgram = "t3";
                platforms = builtins.attrNames releases;
                sourceProvenance = [ prev.lib.sourceTypes.binaryNativeCode ];
              };
            };
        })
      ];
    };
    homeManager =
      { lib, pkgs, ... }:
      {
        # Mirrors t3code-nightly.nix so every fleet host that included the
        # nightly keeps the same shape: x86 desktops stay on the root pin
        # (mkIf), aarch64 hosts pick up the pinned server package.
        programs.t3code.package = lib.mkIf pkgs.stdenv.hostPlatform.isAarch64 (
          lib.mkForce pkgs.t3code-stable010
        );
        systemd.user.services.t3code-web.Service.ExecStart =
          lib.mkForce "${pkgs.t3code-stable010}/bin/t3 serve --mode web";
      };
  };
}
