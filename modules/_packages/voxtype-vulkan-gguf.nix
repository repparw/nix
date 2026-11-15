{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  versionCheckHook,

  clang,
  cmake,
  gitMinimal,
  libclang,
  makeBinaryWrapper,
  pkg-config,

  alsa-lib,
  dotool,
  libnotify,
  openssl,
  pciutils,
  pulseaudio,
  shaderc,
  spirv-headers,
  sqlite,
  vulkan-headers,
  vulkan-loader,
  wl-clipboard,
  wtype,
  which,
}:
# Voxtype 1.2.0 with Vulkan inference and the GGUF worker that upstream's
# release binaries ship (Dockerfile.vulkan, scripts/package.sh): the daemon is
# built with `gpu-vulkan` (whisper.cpp on Vulkan plus the gguf, parakeet-gguf
# and cohere-gguf client features), and `voxtype-gguf-worker` — a separate
# workspace crate hosting transcribe.cpp 0.2.3 — provides the out-of-process
# GGUF inference host for Parakeet models. The daemon resolves the worker
# beside its own executable first (src/transcribe/gguf_subprocess.rs
# worker_beside_executable), so both binaries must live in the same bin dir.
#
# nixpkgs still packages 1.1.1, which has no GGUF support; replace this local
# build with the official package once nixpkgs carries 1.2.0. The openvino
# Cargo.lock patch is copied verbatim from nixpkgs' 1.1.1 package — the 1.2.0
# lock pins the same openvino-rs git fork with the unvendorable submodule.
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "voxtype";
  version = "1.2.0";

  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "peteonrails";
    repo = "voxtype";
    tag = "v${finalAttrs.version}";
    hash = "sha256-uOyii8k3vN/Jxkd+87Wg6gU7+RfzMV5Dz3KkIYhriOU=";
  };

  # See the comment above; drop together with this package once nixpkgs has
  # voxtype 1.2.0.
  cargoPatches = [ ./voxtype-openvino-genai-from-crates-io.patch ];

  cargoHash = "sha256-Gv+2q3Zi193BjsuUrnpk2Kfb37L5m9A9S6OOC/9xy1Q=";

  # gpu-vulkan = whisper-rs/vulkan + gguf + parakeet-gguf + cohere-gguf
  # (Cargo.toml [features]); the default `itn` feature stays enabled.
  buildFeatures = [ "gpu-vulkan" ];

  nativeBuildInputs = [
    cmake
    clang
    gitMinimal # Required by whisper.cpp cmake
    makeBinaryWrapper
    pkg-config
    shaderc
    vulkan-headers
    vulkan-loader
  ];

  buildInputs = [
    alsa-lib
    openssl
    spirv-headers # ggml-vulkan cmake find_package(SPIRV-Headers)
    sqlite # libsqlite3-sys links -lsqlite3; nixpkgs no longer puts it on the link path
    vulkan-headers
    vulkan-loader
  ];

  env = {
    # NOTE: set LIBCLANG_PATH so bindgen can locate libclang
    LIBCLANG_PATH = "${lib.getLib libclang}/lib";

    # NOTE: Ensure reproducible builds targeting AVX2-capable CPUs (x86-64-v3),
    # matching the nixpkgs package and upstream's release binaries.
    RUSTFLAGS = lib.optionalString (
      stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64
    ) "-C target-cpu=x86-64-v3";
  };

  # The vendored shader generator retains a future for every glslc invocation,
  # even when its concurrency limit is one. Run the compiles synchronously to
  # avoid exhausting thread/process resources during the large matmul shader set.
  # A failed glslc invocation otherwise leaves empty generated C++ files, which
  # only fail at the final link with undefined matmul_*_{data,len} symbols.
  postPatch = ''
    shaderGen="$cargoDepsCopy/source-registry-0/whisper-rs-sys-0.15.0/whisper.cpp/ggml/src/ggml-vulkan/vulkan-shaders/vulkan-shaders-gen.cpp"
    test -f "$shaderGen"
    substituteInPlace "$shaderGen" \
      --replace-fail \
      '    compiles.push_back(std::async(
        string_to_spv_func, name, input_filepath, out_path, defines, coopmat, generate_dep_file, std::move(slot)));' \
      '    string_to_spv_func(name, input_filepath, out_path, defines, coopmat, generate_dep_file, std::move(slot));'
    substituteInPlace "$shaderGen" \
      --replace-fail \
      '            if (data.empty()) {
                continue;
            }' \
      '            if (data.empty()) {
                throw std::runtime_error("Missing compiled Vulkan shader: " + name + " (" + path + ")");
            }'
  '';

  preBuild = ''
    # cargoBuildHook reads NIX_BUILD_CORES after preBuild to set Cargo -j.
    # cmake-rs propagates that Cargo job count as CMake --parallel, which
    # overrides CMAKE_BUILD_PARALLEL_LEVEL. Bound both so the Vulkan shader
    # generator doesn't drop outputs under parallel build pressure.
    export NIX_BUILD_CORES=1
    export CMAKE_BUILD_PARALLEL_LEVEL=1
    export VULKAN_SDK="${shaderc.bin}"
    export Vulkan_INCLUDE_DIR="${vulkan-headers}/include"
    export Vulkan_LIBRARY="${vulkan-loader}/lib/libvulkan.so"
  '';

  # The GGUF worker is a workspace member, not part of the default package
  # build; upstream's release packaging runs it as a second cargo invocation
  # with the matching Vulkan feature. Same target/profile as cargoBuildHook so
  # the shared dependencies are not rebuilt.
  postBuild = ''
    cargo build --offline --jobs 1 \
      --target ${stdenv.hostPlatform.rust.cargoShortTarget} \
      --profile release \
      -p voxtype-gguf-worker --features vulkan
  '';

  # cargo test wants a D-Bus session and audio devices; the runtime smoke
  # tests in docs cover the behavior that matters here.
  doCheck = false;

  postInstall = ''
    install -Dm644 config/default.toml \
      $out/share/voxtype/default-config.toml
    install -Dm755 target/${stdenv.hostPlatform.rust.cargoShortTarget}/release/voxtype-gguf-worker \
      $out/bin/voxtype-gguf-worker

    wrapProgram $out/bin/voxtype \
      --prefix PATH : ${
        lib.makeBinPath [
          libnotify
          pulseaudio # pactl for Voxtype media ducking
          which
          pciutils # GPU detection for GGUF worker backend selection
          dotool
          wl-clipboard
          wtype
        ]
      }
  '';

  nativeInstallCheckInputs = [
    versionCheckHook
  ];
  doInstallCheck = true;

  meta = {
    description = "Voice-to-text with push-to-talk for Wayland compositors (Vulkan + GGUF worker)";
    longDescription = ''
      Voxtype is a push-to-talk voice-to-text daemon for Linux, built here with
      the Vulkan whisper backend and the transcribe.cpp GGUF worker that runs
      Parakeet (and other) GGUF models on the GPU.
    '';
    homepage = "https://voxtype.io";
    changelog = "https://github.com/peteonrails/voxtype/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "voxtype";
  };
})
