{ den, ... }:
{
  # Version bridge for nixpkgs#575132 (t3code 0.0.45 -> 0.1.0). Desktop
  # uses the pinned Nixpkgs recipe with only the upstream version and hashes
  # overridden; ARM hosts use the upstream server archive.
  # When the root pin includes 0.1.0, this watcher removes the whole bridge.
  # The separate t3code-split watcher owns the server-only layer until
  # nixpkgs#555814 reaches the pin.
  den.aspects.ai.provides.t3code-stable010 = {
    nixos =
      {
        config,
        lib,
        ...
      }:
      {
        nixpkgs.overlays = [
          (
            final: prev:
            {
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
            }
            // lib.optionalAttrs (config.modules.desktop.enable or false) {
              t3code = prev.t3code.override {
                t3code-unwrapped = prev.t3code.unwrapped.overrideAttrs (
                  finalAttrs: old: {
                    version = "0.1.0";
                    src = prev.fetchFromGitHub {
                      owner = "pingdotgg";
                      repo = "t3code";
                      tag = "v${finalAttrs.version}";
                      hash = "sha256-P82DqoY1E9wtROwu5Nr7MB/I1PdmZHWXXR4nRa4GWXM=";
                    };
                    pnpmDeps = prev.fetchPnpmDeps {
                      pnpm = prev.pnpm_11;
                      inherit (finalAttrs)
                        pname
                        version
                        src
                        pnpmWorkspaces
                        ;
                      fetcherVersion = 4;
                      hash = "sha256-oX4tOu20tYO3ci7VvSEL8eFgxAYWp5HlQFSfAWJGJmg=";
                    };
                    postPatch = (old.postPatch or "") + ''
                      cp .env.example .env
                    '';
                  }
                );
              };
            }
          )
        ];
      };
    homeManager =
      { lib, pkgs, ... }:
      {
        # ARM hosts use the release archive for the server-only CLI; Alpha's
        # desktop package uses the pinned recipe with the PR's version hashes.
        programs.t3code.package = lib.mkIf pkgs.stdenv.hostPlatform.isAarch64 (
          lib.mkForce pkgs.t3code-stable010
        );
        systemd.user.services.t3code-web.Service.ExecStart =
          lib.mkForce "${pkgs.t3code-stable010}/bin/t3 serve --mode web";
      };
  };
}
