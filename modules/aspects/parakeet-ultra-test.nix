{
  den,
  lib,
  ...
}:
{
  # Temporary alpha-only Parakeet Ultra evaluation (dictation model experiment,
  # against the deployed Whisper Small). Adds an onnx-capable voxtype build
  # (Vulkan whisper kept, parakeet via system onnxruntime load-dynamic) and the
  # pinned moondream/parakeet-ultra ONNX conversion, then flips the dictation
  # engine to parakeet. The dictation aspect stays untouched: everything this
  # aspect changes is reverted by removing it from the repparw aspect includes
  # in modules/entities.nix (or by redeploying the previous generation).
  #
  # Whisper Small remains the landed default; if the evaluation adopts Ultra,
  # the package swap and [parakeet] block graduate into
  # modules/aspects/ai/dictation.nix with engine still selectable per config,
  # and this aspect retires like moonshine-pr227-test did.
  den.aspects.parakeet-ultra-test = {
    nixos =
      {
        lib,
        pkgs,
        ...
      }:
      {
        nixpkgs.overlays = [
          (final: prev: {
            parakeet-ultra-onnx = final.callPackage ../_packages/parakeet-ultra-onnx.nix { };
            voxtype-parakeet = prev.voxtype-vulkan.override { onnxSupport = true; };
            vox-bench = final.callPackage ../_packages/vox-bench.nix { };
          })
        ];
      };

    homeManager =
      {
        lib,
        pkgs,
        ...
      }:
      {
        services.voxtype = {
          package = lib.mkForce pkgs.voxtype-parakeet;
          settings = {
            engine = lib.mkForce "parakeet";
            parakeet = {
              model = "${pkgs.parakeet-ultra-onnx}";
              model_type = "tdt";
            };
          };
        };

        home.packages = [
          # Benchmark harness for the evaluation; graduates or retires with
          # this aspect.
          pkgs.vox-bench
        ];
      };
  };
}
