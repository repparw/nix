{
  lib,
  fetchurl,
}:
# Moondream Parakeet Ultra (post-trained nvidia/parakeet-tdt-0.6b-v3) as a
# transcribe.cpp GGUF conversion by handy-computer — the same repo and pinned
# revision as voxtype v1.2.0's curated catalog (src/setup/model.rs,
# PARAKEET_GGUF_MODELS: revision a1539be1, sha256 007a5976..., 740,363,168
# bytes). Q8_0 matched the F16 reference on WER and Vulkan speed in upstream
# testing and is the catalog default for new Parakeet selections. Keeps all 25
# European languages (incl. en, es), so the parakeet engine needs no explicit
# language setting; the whisper fallback retains its own language list.
#
# Parakeet Ultra keeps v3's architecture, so the worker's TDT decoder needs no
# per-model config. Model selected via the absolute store path in
# services.voxtype settings ([parakeet] model = path); voxtype resolves
# absolute paths without a registry entry.
fetchurl {
  name = "parakeet-ultra-Q8_0.gguf";
  url = "https://huggingface.co/handy-computer/parakeet-ultra-gguf/resolve/a1539be1b849ea7463b88343e5277b373d0c4ea9/parakeet-ultra-Q8_0.gguf";
  hash = "sha256-AHpZdh6SWHefGJ3zlrUNErg7tbeeZt9LlVwjDS8qClk=";

  meta = {
    description = "Moondream Parakeet Ultra Q8_0 GGUF (25-language TDT dictation model)";
    homepage = "https://huggingface.co/handy-computer/parakeet-ultra-gguf";
    license = lib.licenses.cc-by-40;
    platforms = lib.platforms.linux;
  };
}
