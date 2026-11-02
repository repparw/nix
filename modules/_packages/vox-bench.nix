{
  writeShellApplication,
  coreutils,
  python3,
  time,
}:
# Offline transcription benchmark for voxtype engines over a fixed sample set.
#
# Usage:
#   vox-bench LABEL ENGINE MODEL_PATH SAMPLES_DIR [OUT_DIR]
#
# The voxtype binary is taken from VOXTYPE_BIN (default: `voxtype` on PATH),
# so the deployed build and the onnx test build can be benchmarked explicitly.
# MODEL_PATH may be empty to use whatever the binary's config selects.
#
# SAMPLES_DIR holds pairs: <name>.wav (16 kHz mono preferred) and <name>.txt
# (reference transcript). OUT_DIR defaults to ./vox-bench-<label> and receives
# one transcript file per clip (raw model output, for separate punctuation and
# capitalization review) plus a results.md table.
#
# WER is computed after normalization: lowercase, strip punctuation, split on
# whitespace. Punctuation quality is NOT part of WER; review the dumped
# transcripts for it. Cold latency is the first inference of the process for
# that clip; the remaining runs measure warm behavior.
writeShellApplication {
  name = "vox-bench";
  runtimeInputs = [
    coreutils
    python3
    time
  ];
  text = ''
    set -euo pipefail

    label="''${1:?usage: vox-bench LABEL ENGINE MODEL_PATH SAMPLES_DIR [OUT_DIR]}"
    engine="''${2:?}"
    model="''${3-}" # empty string uses the binary's configured default
    samples="''${4:?}"
    out="''${5:-vox-bench-$label}"
    voxtype_bin="''${VOXTYPE_BIN:-voxtype}"

    mkdir -p "$out"

    flags=()
    # Optional config file (VOXTYPE_CONFIG): needed for engines whose model is
    # configured in a [section] table rather than resolvable via --model, e.g.
    # a parakeet model given as an absolute store path. Must precede the
    # `transcribe` subcommand; -c is a top-level option.
    cfgflags=()
    if [ -n "''${VOXTYPE_CONFIG:-}" ]; then
      cfgflags+=(-c "$VOXTYPE_CONFIG")
    fi
    if [ -n "$model" ]; then
      flags+=(--model "$model")
    fi

    for wav in "$samples"/*.wav; do
      name="$(basename "''${wav%.wav}")"
      ref="$samples/$name.txt"
      if [ ! -f "$ref" ]; then
        echo "vox-bench: missing reference $ref, skipping $name" >&2
        continue
      fi

      for run in 1 2 3; do
        # GNU time reports wall clock and peak RSS. Voxtype prints per-phase
        # timings and the transcript on stdout; the transcript is the last
        # non-empty stdout line (progress logs precede it). Every invocation
        # is a fresh process, so the wall clock includes model loading each
        # time; the parsed log timings separate load from inference. The
        # greps tolerate absence (|| true): engines log different shapes, and
        # set -e would otherwise kill the loop on a missed match.
        command time -f '%e %M' "$voxtype_bin" "''${cfgflags[@]}" transcribe "$wav" \
          --engine "$engine" "''${flags[@]}" >"$out/$name.stdout" 2>"$out/$name.time"
        read -r secs rss < <(tail -n 1 "$out/$name.time")
        load_s="$(grep -ioE 'model loaded in [0-9.]+s' "$out/$name.stdout" | head -1 | grep -oE '[0-9.]+' || true)"
        inf_s="$(grep -ioE 'transcription completed in [0-9.]+s' "$out/$name.stdout" | head -1 | grep -oE '[0-9.]+' || true)"
        printf '%s %s %s %s %s\n' "$run" "$secs" "$rss" "''${load_s:-NA}" "''${inf_s:-NA}" >>"$out/$name.latency"
        if [ "$run" = 1 ]; then
          awk 'NF { last = $0 } END { print last }' "$out/$name.stdout" >"$out/$name.$engine.txt"
        fi
      done
    done

    python3 - "$out" "$engine" "$samples" <<'PY'
    import re, sys, pathlib

    out_dir = pathlib.Path(sys.argv[1])
    engine = sys.argv[2]
    samples = pathlib.Path(sys.argv[3])

    def normalize(text):
        text = text.lower()
        text = re.sub(r"[^\w\s]", "", text, flags=re.UNICODE)
        return text.split()

    def wer(ref, hyp):
        # Levenshtein on word lists: sub=1, ins=1, del=1.
        r, h = len(ref), len(hyp)
        prev = list(range(h + 1))
        for i in range(1, r + 1):
            cur = [i] + [0] * h
            for j in range(1, h + 1):
                cur[j] = min(prev[j] + 1, cur[j-1] + 1, prev[j-1] + (ref[i-1] != hyp[j-1]))
            prev = cur
        return prev[h] / r if r else float("nan")

    rows = []
    for ref_path in sorted(out_dir.glob(f"*.{engine}.txt")):
        name = ref_path.name.removesuffix(f".{engine}.txt")
        ref_file = samples / f"{name}.txt"
        hyp = ref_path.read_text(encoding="utf-8")
        if not ref_file.exists():
            continue
        ref = ref_file.read_text(encoding="utf-8")
        lat = [l.split() for l in (out_dir / f"{name}.latency").read_text().splitlines()]
        wall = [float(x[1]) for x in lat]
        load = [float(x[3]) for x in lat if x[3] != "NA"]
        inf = [float(x[4]) for x in lat if x[4] != "NA"]
        rss = max((int(x[2]) for x in lat), default=0)
        rows.append((name, wer(normalize(ref), normalize(hyp)),
                     load[0] if load else float("nan"),
                     sum(inf)/len(inf) if inf else float("nan"),
                     sum(wall)/len(wall), rss, hyp))

    lines = ["| clip | WER | load (s) | inference avg (s) | wall avg (s) | peak RSS (KiB) |",
             "|---|---|---|---|---|---|"]
    for name, w, ld, inf_avg, wall_avg, rss, _ in rows:
        lines.append(f"| {name} | {w:.3f} | {ld:.2f} | {inf_avg:.2f} | {wall_avg:.2f} | {rss} |")
    if rows:
        lines.append("")
        lines.append(f"**mean WER:** {sum(r[1] for r in rows)/len(rows):.3f}  ")
        lines.append(f"**mean inference:** {sum(r[3] for r in rows)/len(rows):.2f}s  ")
        lines.append(f"**mean wall (incl. model load):** {sum(r[4] for r in rows)/len(rows):.2f}s")
    (out_dir / "results.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))
    PY
  '';
}
