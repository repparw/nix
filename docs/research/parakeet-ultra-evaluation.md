---
type: Research Note
title: Parakeet Ultra Dictation Evaluation
description: Compatibility and benchmark plan for moondream/parakeet-ultra ONNX as the voxtype dictation engine on alpha.
when: Read when changing the dictation engine or model, or retiring the parakeet-ultra test aspect.
resource: modules/aspects/parakeet-ultra-test.nix
tags: [research, dictation, voxtype, parakeet, asr]
---

# Parakeet Ultra dictation evaluation (alpha)

Evaluation of **Parakeet Ultra** (moondream's post-trained
`nvidia/parakeet-tdt-0.6b-v3`) as a dictation model for voxtype, against the
deployed Whisper Small. This is an evaluation, not a migration: Whisper Small
remains the landed default until the benchmark says otherwise.

## Deployment state (phase 1 findings)

- Deployed: `voxtype-vulkan` 1.1.0 (nixpkgs, flake rev `0c721967`, Oct 14),
  `engine = "whisper"`, `model = "small"` (multilingual), `language = ["en", "es"]`,
  Vulkan acceleration. Verified live on alpha: config, package closure contains
  `vulkan-loader`, models dir holds only `ggml-*.bin`.
- Parakeet support requires the ONNX feature: nixpkgs builds it as
  `voxtype-vulkan.override { onnxSupport = true; }` (buildFeatures gains
  `parakeet-load-dynamic`; whisper keeps Vulkan). The deployed binary cannot
  run parakeet at all.
- The engine table in voxtype's README lists Parakeet as English-only; that
  describes v2-era models. `parakeet-tdt-0.6b-v3` and Ultra are 25-language
  models (incl. es), and voxtype's catalog default is `parakeet-tdt-0.6b-v3`.

## Compatibility verdict

**Works with a documented rename (applied declaratively), pending live test.**

- Conversion: [beshkenadze/parakeet-ultra-onnx](https://huggingface.co/beshkenadze/parakeet-ultra-onnx)
  (CC-BY-4.0, sha256-pinned in `modules/_packages/parakeet-ultra-onnx.nix`).
  Encoder fp16 (1.22 GB), decoder fp32 single-file (72 MB), `vocab.txt`
  identical to v3's. Same graph IO names as the istupakov v3 exports; the
  conversion README explicitly names parakeet-rs as a compatible runtime.
- parakeet-rs 0.3.5 (pinned by voxtype 1.1.1): `ParakeetTDTModel` probes
  `encoder-model.onnx`, `encoder.onnx`, `encoder-model.int8.onnx`, then any
  `encoder*.onnx`; the conversion publishes `encoder-model.fp16.onnx`, so the
  canonical name is required for the exact-name path (and for voxtype's TDT
  auto-detection and manifest-less health checks). `linkFarm` provides the
  renamed symlink; bytes unchanged.
- Decoder hidden size (640) hardcoded in parakeet-rs matches Ultra (same
  architecture/tokenizer as v3); vocab size is read from `vocab.txt`.
- Model selection needs no upstream changes: `[parakeet] model = "/nix/store/…"`
  absolute path is resolved directly by voxtype. Ultra is not in voxtype's R2
  registry (R2-only download policy), so a pinned Nix derivation is also the
  only reproducible channel.
- fp16 on CPU ONNX Runtime: the CPU EP consumes fp16 graphs; the empirical
  smoke test (below) is the final word. Fallback if the fp16 encoder fails:
  the fp32 encoder from Olicorne/parakeet-tdt-0.6b-v3-ultra-onnx.
- AMD GPU: voxtype has a `parakeet-migraphx` feature, but nixpkgs' onnxruntime
  does not ship the MIGraphX EP, and RDNA2 gfx1031 (RX 6700 XT) is not an
  official ROCm target. Per the evaluation brief, Ultra runs on CPU here.

## Upstream context

- parakeet-rs master actively supports Ultra (own export script option,
  burn-backend parity tests); 0.3.5 predates that but loads the same files.
- voxtype roadmap (PR #795, merged): **2.0 removes ONNX Runtime** in favor of
  ggml/GGUF engines; parakeet.cpp (#483, PR #863) already loads Moondream
  Ultra GGUF by path. An ONNX-parakeet adoption has a shelf life of roughly
  the 1.x line; a 2.0 world would re-do this via parakeet-cpp.
- Per-profile engine switching (issue #519, milestone 1.3.0) does not exist in
  1.1.1; engine switches are a config change + daemon restart.

## Test deployment

`modules/aspects/parakeet-ultra-test.nix` (attached to alpha's repparw user in
`modules/entities.nix`, pattern after `moonshine-pr227-test`):

- overlay: `parakeet-ultra-onnx` (pinned model), `voxtype-parakeet`
  (onnx-capable build), `vox-bench` (benchmark harness);
- HM: `services.voxtype.package = mkForce voxtype-parakeet`, `engine = mkForce
  "parakeet"`, `[parakeet] model = store path, model_type = "tdt"`.
- `modules/aspects/ai/dictation.nix` is untouched; retiring the aspect (remove
  from entities.nix + redeploy) restores today's exact deployment. Generations
  and the boot entry provide the additional rollback path.

## Benchmark

Harness: `vox-bench LABEL ENGINE MODEL SAMPLES_DIR` (3 runs per clip; cold,
warm average, peak RSS; WER after lowercase + punctuation-stripping
normalization; raw transcripts dumped for separate punctuation review). The
voxtype binary under test is chosen via `VOXTYPE_BIN`.

Samples: FLEURS dev `en_us` + `es_419` (CC-BY-4.0), 3 clips each, fetched to
`/tmp/opencode/bench-samples` (not committed). **Known gaps** requiring real
recordings from alpha's mic: conversational (non-read) speech, Argentine
(Rioplatense) Spanish specifically, en/es code-switching, dictation-style
technical vocabulary (NixOS, systemd, flake, …), and short push-to-talk
utterances. FLEURS es_419 is Latin-American but not specifically Rioplatense;
the es numbers are a proxy, and the qualitative live-dictation test on alpha
covers the gap anecdotally.

Baseline arms:

| arm | engine | model | binary | accel |
|---|---|---|---|---|
| whisper-small (current) | whisper | small | deployed voxtype-vulkan 1.1.0 | Vulkan |
| parakeet-ultra | parakeet | ultra (fp16 encoder) | voxtype-parakeet 1.1.1 | CPU |

Results: recorded in the PR description and `decisions.tsv` after the run.

## Decision criteria

Adopt Ultra only if it beats Whisper Small on es + en WER at comparable
live latency, or if the latency/quality tradeoff clearly favors dictation use
(e.g., Whisper Small's multilingual small model is markedly slower warm).
Otherwise retain Whisper Small and revisit when voxtype 2.0's parakeet.cpp
path lands.
