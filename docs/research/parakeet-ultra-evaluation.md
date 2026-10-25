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

## Deployment blocker (pre-existing, unrelated to this evaluation)

A full alpha closure build from current main fails on
`nodejs-slim-24.22.1` (produced by the `nodejs-security` overlay,
`modules/aspects/nodejs-security.nix`): its output check rejects
`out` inside the `libv8` output check while the derivation itself declares
`out` ("output check for 'libv8' contains output name 'out', but this is not
a valid output of this derivation. Valid outputs are [corepack, dev, libv8,
npm]"). The pristine flake nixpkgs (`02c087f3`) nodejs-slim is 24.21.0, so the
failing 24.22.1 build comes from the repo's own security overlay; the
`nodejs refactor` PR (#334662) shows libv8 output handling is mid-change
upstream. Effect: `nix build
.#nixosConfigurations.alpha.config.system.build.toplevel` (and therefore
deploy-rs activation) is blocked for alpha at this revision for every change,
not just this one. The evaluation therefore proceeds with targeted builds and
a manually run daemon, and no activation until the nodejs issue is fixed
separately.

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

Results (2026-10-25, alpha, voxtype 1.1.1 for BOTH arms — same binary, same
energy VAD; whisper via Vulkan, Ultra via ORT CPU; FLEURS dev, 8 clips, 3 runs
each; WER after lowercase + punctuation-stripping normalization; load and
inference parsed from voxtype's own log lines because each CLI invocation is a
fresh process that reloads the model):

| arm | mean WER | load (cold) | inference avg | wall avg | peak RSS |
|---|---|---|---|---|---|
| whisper small (Vulkan) | 0.059 | ~0.34s | **0.32s** | **0.68s** | ~0.17 GB |
| parakeet ultra (CPU) | **0.038** | ~2.6s | 0.89s | 3.81s | ~2.8 GB |

Per-clip: both engines perfect on 5/8; Ultra additionally perfect on
`4175831345558885921` (EN proper nouns; whisper 0.158: "are"→"and",
"harbours"→"harbors", lost sentence break) and `809628312584936889` (ES;
whisper 0.067 plus wrapped a statement in `¿?`). Both show 0.25 on
`18352318493708579158` — a tokenization artifact of the reference's
"WiFi door bell" vs both engines' better "Wi-Fi doorbell"; qualitative output
of both is superior to the reference there.

Interpretation for dictation (the daemon keeps the model loaded, so live
push-to-talk latency is the inference number, not the wall clock):

- **Accuracy**: Ultra wins on this read-speech set (0.038 vs 0.059) and its
  Spanish output was byte-identical to the reference where whisper
  paraphrased. Punctuation/capitalization quality is excellent on both; Ultra
  was more faithful.
- **Latency**: whisper-small on Vulkan is ~2.7× faster to transcribe
  (0.32s vs 0.89s on 2.7–12s clips). Cold start: whisper 0.34s, Ultra 2.6s
  (paid once per daemon start, or at first dictation).
- **Memory**: Ultra holds ~2.8 GB resident (fp16 encoder) vs whisper ~0.17 GB.
  On-demand loading can move this out of steady state at the cost of
  first-utterance latency.

An earlier whisper-arm run on the deployed 1.1.0 binary showed 2 clips
discarded by VAD ("0.00s speech") that 1.1.1 transcribes fine — a VAD
behavior difference between voxtype versions, worth knowing when comparing
across versions; the table above deliberately uses one binary for both arms.

## Decision criteria

Adopt Ultra only if it beats Whisper Small on es + en WER at comparable
live latency, or if the latency/quality tradeoff clearly favors dictation use
(e.g., Whisper Small's multilingual small model is markedly slower warm).
Otherwise retain Whisper Small and revisit when voxtype 2.0's parakeet.cpp
path lands.
