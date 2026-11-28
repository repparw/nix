{ den, ... }:
{
  # Temporary backport of NixOS/nixpkgs#589125 until the fleet pin includes 0.1.13.
  den.aspects.ai.provides.t3code.provides.to-hosts.nixos =
    { lib, ... }:
    {
      nixpkgs.overlays = lib.mkBefore [
        (
          final: prev:
          let
            t3codeUnwrapped = prev.t3code.unwrapped.overrideAttrs (
              finalAttrs: old: {
                version = "0.1.13";

                src = prev.fetchFromGitHub {
                  owner = "pingdotgg";
                  repo = "t3code";
                  tag = "v${finalAttrs.version}";
                  hash = "sha256-Frk9YQmkR5MrIo0+eMmYqFkit/Y2tf3JkOXy1c6srbs=";
                };

                nativeBuildInputs =
                  (old.nativeBuildInputs or [ ])
                  ++ prev.lib.optionals prev.stdenv.hostPlatform.isLinux [
                    prev.autoPatchelfHook
                  ];

                buildInputs =
                  (old.buildInputs or [ ])
                  ++ prev.lib.optionals prev.stdenv.hostPlatform.isLinux [
                    prev.stdenv.cc.cc.lib
                    prev.vulkan-loader
                  ];

                pnpmDeps = prev.fetchPnpmDeps {
                  pnpm = prev.pnpm_12;
                  inherit (finalAttrs)
                    pname
                    version
                    src
                    pnpmWorkspaces
                    ;

                  fetcherVersion = 5;
                  hash = "sha256-5ncmrXOIU3sxrB6XaauC/6PPL4YyHaUO62ST1y1O2B8=";
                };

                preBuild = (old.preBuild or "") + ''
                  patchShebangs apps/*/node_modules packages/*/node_modules scripts/node_modules
                '';

                dontAutoPatchelf = true;
                autoPatchelfFlags = [ "--preserve-origin" ];

                postFixup = prev.lib.optionalString prev.stdenv.hostPlatform.isLinux ''
                  # Resolve libstdc++ and Vulkan through buildInputs, retaining $ORIGIN for
                  # the speech library's sibling ggml libraries.
                  autoPatchelf \
                    "$out"/libexec/t3code/node_modules/.pnpm/node-pty@*/node_modules/node-pty/prebuilds/linux-${prev.stdenv.hostPlatform.node.arch} \
                    "$out"/libexec/t3code/node_modules/.pnpm/@koromix+koffi-linux-${prev.stdenv.hostPlatform.node.arch}@*/node_modules/@koromix/koffi-linux-${prev.stdenv.hostPlatform.node.arch}/linux_${prev.stdenv.hostPlatform.node.arch} \
                    "$out"/libexec/t3code/node_modules/.pnpm/@transcribe-cpp+linux-${prev.stdenv.hostPlatform.node.arch}-cpu-vulkan@*/node_modules/@transcribe-cpp/linux-${prev.stdenv.hostPlatform.node.arch}-cpu-vulkan
                '';

                doInstallCheck =
                  prev.stdenv.hostPlatform.isLinux && prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform;
                installCheckPhase = ''
                  runHook preInstallCheck

                  # The standalone Node CLI can mask missing C++ runtime dependencies;
                  # exercise local dictation with the same runtime as the desktop worker.
                  ELECTRON_RUN_AS_NODE=1 ${prev.lib.getExe prev.electron_44} --input-type=module -e '
                    const speech = await import(process.argv[1]);
                    if (!speech.getAvailableBackends().some(backend => backend.kind === "cpu")) {
                      throw new Error("Native speech CPU backend is unavailable");
                    }
                  ' "$out/libexec/t3code/apps/server/node_modules/transcribe-cpp/dist/index.js"

                  runHook postInstallCheck
                '';
              }
            );
          in
          if prev ? t3code && !(prev ? t3code-cli) then
            {
              t3code =
                if prev.lib.versionOlder prev.t3code.version "0.1.13" then
                  prev.t3code.override {
                    t3code-unwrapped = t3codeUnwrapped;
                    t3code-resource-monitor = prev.t3code.resourceMonitor.overrideAttrs (old: {
                      inherit (t3codeUnwrapped) src version;
                      sourceRoot = "${t3codeUnwrapped.src.name}/native/resource-monitor";
                      cargoDeps = prev.rustPlatform.fetchCargoVendor {
                        inherit (t3codeUnwrapped) src;
                        inherit (old) pname;
                        inherit (t3codeUnwrapped) version;
                        sourceRoot = "${t3codeUnwrapped.src.name}/native/resource-monitor";
                        hash = "sha256-QartZALjE2BxgfKcV3CJjtG6oSNE/Vcbz2ESx1UrRbk=";
                      };
                    });
                  }
                else
                  prev.t3code;
            }
          else
            { }
        )
      ];
    };
}
