---
type: Research Note
title: Parakeet Ultra Dictation Evaluation
description: Compatibility and benchmark plan for moondream/parakeet-ultra as the voxtype dictation engine on alpha, and the 1.2.0 GGUF/Vulkan migration.
when: Read when changing the dictation engine or model, or retiring the parakeet-ultra test aspect.
resource: modules/aspects/ai/dictation.nix
tags: [research, dictation, voxtype, parakeet, asr]
---

# Parakeet Ultra dictation evaluation (alpha)

**Update (2026-11-11): Ultra now runs as a Q8 GGUF on Vulkan.** voxtype 1.2.0
replaced the ONNX Parakeet path with transcribe.cpp's GGUF worker, and the
deployment moved off CPU ONNX Runtime onto the RX 6700 XT. The ONNX model
derivation and the `onnxSupport` build flag are gone; Whisper Small stays
configured as the rollback engine. See "GGUF on Vulkan" below.

**Decision (2026-10-25): adopted.** After the benchmark and a live dictation
trial on alpha ("works fine"), the default dictation engine flipped to
Parakeet Ultra in `modules/aspects/ai/dictation.nix`, with Whisper Small kept
configured as the rollback engine. Language behavior: parakeet has no
language knob (no force, no block — verified against `ParakeetConfig` and
parakeet-rs); it transcribes in any of its 25 languages. Whisper Small
remains the only engine with a real language allowlist
(`language = ["en", "es"]`); if cross-language confusion appears in daily
dictation, the options are flipping `engine` back to whisper or an upstream
output-side language-filter request. Shelf life: voxtype 2.0 removes ONNX
Runtime (PR #795); the durable Ultra path is parakeet.cpp (#483/#863), which
already loads Moondream Ultra GGUF by path.

Evaluation of **Parakeet Ultra** (moondream's post-trained
`nvidia/parakeet-tdt-0.6b-v3`) as a dictation model for voxtype, against the
deployed Whisper Small. The evaluation phase kept Whisper Small as the landed
default until the benchmark and live trial said otherwise.

## Deployment state

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

Those notes describe the 1.1.x ONNX deployment. The current deployment state
is the GGUF/Vulkan setup below.

## Compatibility verdict (ONNX path, retired)

**Works with a documented rename (applied declaratively), pending live test.**

This section records the 1.1.x ONNX evaluation. The ONNX model derivation has
been removed; see "GGUF on Vulkan" for the current path.

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

## GGUF on Vulkan (2026-11-11)

voxtype 1.2.0 makes the GGUF path the primary one: `parakeet` with a `.gguf`
model is served by the out-of-process `voxtype-gguf-worker` (transcribe.cpp
0.2.3), not by ONNX Runtime. That removes the CPU-only constraint above, so
Ultra now runs on the GPU.

**Package.** nixpkgs still carries 1.1.1, which has no GGUF support, so
`modules/_packages/voxtype-vulkan-gguf.nix` builds 1.2.0 locally with the
`gpu-vulkan` feature (whisper Vulkan + `gguf` + `parakeet-gguf` +
`cohere-gguf`). The worker is a separate workspace crate, so the derivation
runs a second `cargo build -p voxtype-gguf-worker --features vulkan` and
installs the binary next to the daemon: voxtype resolves the worker beside
its own executable (`src/transcribe/gguf_subprocess.rs`,
`worker_beside_executable`), so both must share a `bin` directory. The
openvino `Cargo.lock` patch is copied verbatim from nixpkgs' 1.1.1 package —
the 1.2.0 lock pins the same openvino-rs git fork with the unvendorable
submodule. `spirv-headers` is a build input because ggml-vulkan's CMake
`find_package(SPIRV-Headers)` needs it, and `sqlite` is a build input because
`libsqlite3-sys` emits `-lsqlite3` and the pinned nixpkgs no longer leaves
SQLite on the link path. The ONNX features are deliberately
not enabled, so the binary links no ONNX Runtime at all.

**Model.** `modules/_packages/parakeet-ultra-gguf.nix` pins
[handy-computer/parakeet-ultra-gguf](https://huggingface.co/handy-computer/parakeet-ultra-gguf)
`parakeet-ultra-Q8_0.gguf` at revision
`a1539be1b849ea7463b88343e5277b373d0c4ea9`, sha256
`007a59761e9258779f189df396b50d12b83bb5b79e66df4b955c230d2f2a0a59`
(740,363,168 bytes). That revision and hash are the ones voxtype 1.2.0's own
catalog lists (`src/setup/model.rs`, `PARAKEET_GGUF_MODELS`), so the pinned
file and upstream's curated entry agree. The 25-language coverage of Ultra is
unchanged, so the parakeet engine still needs no language setting.

**Config.** `[parakeet] model` points at the absolute store path and
`gguf_backend = "vulkan"` pins the backend. The path is resolved directly by
voxtype (absolute paths need no registry entry) and its `.gguf` suffix is what
routes the engine to the GGUF worker instead of ONNX. `model_type` was
dropped: it only applies to the ONNX path, which the GGUF branch returns
before. Whisper Small keeps its `language = ["en", "es"]` allowlist as the
rollback engine.

**Validation on alpha** (RX 6700 XT, RADV NAVI22), against an isolated
daemon with its own config, runtime and data directories, with the live
`voxtype.service` left untouched:

- `voxtype` reports 1.2.0; the daemon spawns
  `voxtype-gguf-worker --engine parakeet --config-json {... "gguf_backend":"vulkan" ...}`
  from the package's own `bin` directory.
- The worker logs `Parakeet GGUF loaded on Vulkan0 [Vulkan0] (AMD Radeon RX
6700 XT (RADV NAVI22))`; the model loads in ~0.6s. `voxtype status --format
json --extended` reports `Backend: GGUF Vulkan (transcribe.cpp)`, and the
  worker writes the backend it actually bound to
  `$XDG_RUNTIME_DIR/voxtype/gguf_backend.json`.
- No silent CPU fallback: with the Vulkan ICD hidden
  (`VK_DRIVER_FILES=/nonexistent`) the explicit `vulkan` backend fails loudly
  (`parakeet: vulkan backend requested but not available`) instead of falling
  back to CPU.
- Transcription, daemon record cycle, `voxtype transcribe` and the worker
  all produce correct English, Spanish and mixed-language text; a 72s
  recording transcribed in 0.82s. The daemon runs with the deployed
  `[vad]` settings (`enabled`, `energy` backend), and every recording passed
  the VAD gate.
- The worker survived repeated record cycles, was respawned on Vulkan after
  being killed, and the daemon recovered the model after a restart. `record
cancel` discards without writing output.
- Whisper Small still transcribes English and Spanish through the same
  build.

The Quickshell OSD recipe stays on its existing pin: v1.2.0's style JSON adds
fields the pinned QML ignores, and the pinned `RecipeRenderer.qml` still
handles the configured `pulse`/`waveform` layers. The OSD frontend binary
ships in the package.

The cleanup options `collapse_restarts`, `repair_sentence_breaks` and
`format_numbers` were left disabled; each needs its own evaluation, and
`format_numbers` in particular changes output text. Auto-submit and LLM
post-processing stay disabled.

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
`modules/aspects/upstream/nodejs-security.nix`): its output check rejects
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

The evaluation ran through `modules/aspects/parakeet-ultra-test.nix` (alpha's
repparw user, pattern after `moonshine-pr227-test`): overlay with
`parakeet-ultra-onnx` (pinned model), `voxtype-parakeet` (onnx-capable build),
and `vox-bench`, plus an engine flip. On adoption everything graduated into
`modules/aspects/ai/dictation.nix` and the test aspect was deleted, so this
section records the retired experiment's shape only.

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

Baseline arms (the 2026-10-25 ONNX/CPU comparison):

| arm                     | engine   | model                | binary                        | accel  |
| ----------------------- | -------- | -------------------- | ----------------------------- | ------ |
| whisper-small (current) | whisper  | small                | deployed voxtype-vulkan 1.1.0 | Vulkan |
| parakeet-ultra          | parakeet | ultra (fp16 encoder) | voxtype-parakeet 1.1.1        | CPU    |

Results (2026-10-25, alpha, voxtype 1.1.1 for BOTH arms — same binary, same
energy VAD; whisper via Vulkan, Ultra via ORT CPU; FLEURS dev, 8 clips, 3 runs
each; WER after lowercase + punctuation-stripping normalization; load and
inference parsed from voxtype's own log lines because each CLI invocation is a
fresh process that reloads the model):

| arm                    | mean WER  | load (cold) | inference avg | wall avg  | peak RSS |
| ---------------------- | --------- | ----------- | ------------- | --------- | -------- |
| whisper small (Vulkan) | 0.059     | ~0.34s      | **0.32s**     | **0.68s** | ~0.17 GB |
| parakeet ultra (CPU)   | **0.038** | ~2.6s       | 0.89s         | 3.81s     | ~2.8 GB  |

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
