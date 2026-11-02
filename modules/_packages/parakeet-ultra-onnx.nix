{
  lib,
  linkFarm,
  fetchurl,
}:
# Moondream Parakeet Ultra (post-trained nvidia/parakeet-tdt-0.6b-v3) exported
# to ONNX by beshkenadze/parakeet-ultra-onnx, laid out the way voxtype's
# parakeet engine and parakeet-rs 0.3.5 expect:
#
# - encoder-model.fp16.onnx is published under that name, but both voxtype's
#   TDT auto-detection (services.voxtype, src/transcribe/parakeet.rs) and
#   parakeet-rs 0.3.5 (ParakeetTDTModel::find_encoder) probe the canonical
#   `encoder-model.onnx` first, and voxtype's manifest-less health check only
#   knows exact names. The conversion README states runtimes looking for
#   `encoder-model.onnx` want the encoder under that name; the bytes are
#   unchanged, only the store-path name differs.
# - decoder_joint-model.onnx and vocab.txt keep their upstream names.
#
# Parakeet Ultra keeps v3's architecture, 8192-token SentencePiece vocab, and
# 25 languages (incl. es), so the hardcoded decoder hidden size (640) and the
# dynamic vocab size in parakeet-rs hold. Model selected via the absolute
# store path in services.voxtype settings ([parakeet] model = path); voxtype
# resolves absolute paths without a registry entry.
linkFarm "parakeet-ultra-onnx" {
  "encoder-model.onnx" = fetchurl {
    url = "https://huggingface.co/beshkenadze/parakeet-ultra-onnx/resolve/main/encoder-model.fp16.onnx";
    hash = "sha256-nOSk2fRX9eCBfKwoiK8L83j2FsMFU4thzus9LuxnRrA=";
  };
  "decoder_joint-model.onnx" = fetchurl {
    url = "https://huggingface.co/beshkenadze/parakeet-ultra-onnx/resolve/main/decoder_joint-model.onnx";
    hash = "sha256-VrQLPKr91SSQ/sVqmeNA+tiZA+KiEmq2HZKb/7WpSNQ=";
  };
  "vocab.txt" = fetchurl {
    url = "https://huggingface.co/beshkenadze/parakeet-ultra-onnx/resolve/main/vocab.txt";
    hash = "sha256-1YVEZ56kvGrFY9H1Ret9R0vWz6Rn8KbiwdwcfTfjw10=";
  };
}
// {
  meta = {
    description = "Moondream Parakeet Ultra ONNX (25-language TDT dictation model)";
    homepage = "https://huggingface.co/beshkenadze/parakeet-ultra-onnx";
    license = lib.licenses.cc-by-40;
    platforms = lib.platforms.linux;
  };
}
