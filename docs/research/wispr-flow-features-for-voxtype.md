---
type: Research Note
title: Wispr Flow Features Worth Bringing to Voxtype
description: Source-backed comparison of current Wispr Flow features with the repository's local Voxtype setup.
resource: modules/aspects/dictation.nix
tags: [dictation, voxtype, wispr-flow, speech]
---

# Wispr Flow Features Worth Bringing to Voxtype

Research date: 2026-07-12.

## Scope and current baseline

The repository pins Voxtype `v0.7.5` with its Vulkan package, the Whisper `base`
model, English and Spanish, audio feedback, a themed Quickshell OSD, a toggle
shortcut, automatic pausing/resuming of media, and transcription notifications
disabled. The comparison below focuses on features that improve everyday
dictation while preserving the setup's local-first character.

Wispr Flow's distinguishing layer is not speech recognition alone. Its official
description emphasizes post-processing: self-correction, filler removal,
punctuation, structured output, personalization, snippets, app context, and
recovery.[^flow-features][^why-flow]

## Recommended additions

### 1. Enable Voxtype's existing cleanup controls

**Recommendation: do first.** Enable `text.filter_filler_words`,
`text.spoken_punctuation`, and `text.smart_auto_submit` explicitly in the
dictation aspect.

- Wispr removes filler words, infers punctuation, formats lists, and understands
  corrections such as “2… actually 3.”[^flow-features]
- The pinned Voxtype release already removes conservative filler words by
  default, supports a broad spoken-punctuation vocabulary, and can strip a final
  spoken “submit” before pressing Enter.[^voxtype-text]
- Explicit configuration documents the intended behavior and protects it from
  upstream default changes. Spoken punctuation and voice submit are opt-in;
  filler filtering is currently on by default.

This yields immediate parity for filler cleanup and explicit punctuation. It
does **not** provide Wispr's semantic course correction (“Tuesday—actually
Wednesday”); that belongs in the local post-processing step below.

### 2. Add a personal dictionary and static voice snippets

**Recommendation: do next.** Declare a small, reviewed replacement table for
names, project vocabulary, common recognition failures, and distinctive trigger
phrases.

Wispr's dictionary both boosts uncommon vocabulary and applies deterministic
misspelling corrections; its snippets replace a spoken trigger phrase with up
to 4,000 characters of saved text.[^dictionary][^snippets] Voxtype's pinned
`text.replacements` performs case-insensitive, word-boundary-preserving phrase
replacement and explicitly supports abbreviation expansion.[^voxtype-text]

This can cover deterministic corrections and static snippets locally, for
example project names, email addresses, recurring sign-offs, or commonly used
commands. Keep triggers unusually specific to avoid accidental expansion. The
gap versus Wispr is management UX: no automatic learning, search UI, usage
ranking, starring, CSV import workflow, or separate dictionary/snippet model.

### 3. Add local AI cleanup, with a raw-text fallback

**Recommendation: prototype behind a separate profile.** Wispr turns rambling
speech into structured writing and handles mid-sentence course corrections;
Voxtype can pipe transcription through any local command or LLM and falls back
to the original transcript if the command fails.[^why-flow][^voxtype-post]

Start with a small local model and a conservative prompt that:

- removes false starts and abandoned alternatives;
- applies the speaker's latest correction;
- adds punctuation and paragraph/list structure;
- preserves names, numbers, technical tokens, language, and meaning;
- never answers or acts on dictated content.

Keep ordinary dictation on the deterministic path until latency and fidelity
are measured. A second “polish” shortcut/profile is safer than making generative
rewriting universal. Preserve the raw transcript in a private local history so
the user can undo AI edits; Wispr now exposes exactly this raw-versus-edited
recovery in transcript history.[^whats-new]

### 4. Add named dictation styles as shortcuts

**Recommendation: pair with local AI cleanup.** Wispr switches writing style by
app category and can learn from writing samples.[^context][^styles] The pinned
Voxtype release already supports named profiles selected at recording time,
each overriding the post-processing command, timeout, and output mode.[^voxtype-profiles]

Useful first profiles would be:

- `raw`: deterministic transcription only;
- `chat`: light cleanup, preserve casual tone, optionally allow spoken submit;
- `email`: complete sentences and restrained professional formatting;
- `code`: preserve identifiers, paths, commands, Markdown, and exact symbols;
- `notes`: paragraphs or bullets, no auto-submit.

Bind profiles to distinct compositor shortcuts or expose a small launcher. This
captures most of the value without reading other applications. Automatic
per-app selection can come later if the compositor exposes the focused app
reliably.

### 5. Add transcript recovery and “paste last transcript”

**Recommendation: high value after cleanup.** Wispr retains interrupted or
failed dictations, supports one-tap retry, exposes raw text before AI edits, and
offers “paste last transcript.”[^whats-new][^long-dictation] This is especially
useful because output injection can fail even when transcription succeeds.

Implement a bounded local history (for example, recent raw and processed text
with timestamps), plus commands to:

- copy or paste the last successful transcript;
- retry local post-processing from the raw transcript;
- choose raw versus polished output;
- clear history immediately and optionally expire it automatically.

Voxtype can already write a recording's transcription to a file, but wiring a
transparent history around normal cursor output may need an upstream hook or a
wrapper change.[^voxtype-cli] Treat retention as opt-in and local-only.

### 6. Add hands-free/long-form dictation as an explicit mode

**Recommendation: useful, but separate from normal dictation.** Wispr has a
continuous hands-free toggle and 20-minute desktop sessions with a warning,
automatic submission, and recovery.[^hands-free][^long-dictation] Voxtype
already supports toggle recording, and its separate meeting mode performs
continuous chunked transcription with timestamped local exports.[^voxtype-readme][^voxtype-meeting]

The practical addition is a clearly distinct shortcut and OSD state for
long-form capture, plus elapsed time and a maximum-duration safeguard. Avoid
silently turning the current quick-dictation toggle into an unlimited recorder.

### 7. Improve language selection

**Recommendation: add an explicit language/profile picker before automatic app
context.** Wispr lets users choose active languages, detects one language per
session, and notes that constraining the candidate set improves accuracy; it
does not reliably alternate languages sentence by sentence.[^languages]

The current Voxtype configuration lists English and Spanish. Add quick `en`,
`es`, and `auto` profiles or a tiny launcher, with the chosen language visible
in the OSD. This is more predictable than relying on detection for every short
utterance and makes failures easy to diagnose.

## Defer or constrain

### Context awareness

Wispr reads nearby accessibility text, app metadata, proper nouns, and—in coding
environments—variable and file names; recent chat messages may also be sent for
processing.[^context] This can improve names, tone, and code prompts, but it
substantially expands the privacy and complexity boundary.

For this setup, prefer explicit profiles and an optional user-invoked command
that captures only selected text. If automatic focused-app context is later
added, make it allowlisted, locally processed, visibly active, disabled in
password/sensitive apps, and independently switchable. Wispr's own controls and
documentation show why context capture needs a separate privacy boundary.[^privacy]

### Usage analytics, sync, and scratchpad

Wispr offers usage insights and cross-device notes/scratchpad syncing.[^whats-new][^scratchpad]
These are lower priority for a system dictation tool and introduce retention,
sync, and UI work. Local history and recovery solve the more important failure
mode first.

## Suggested implementation order

1. Explicit filler filtering, spoken punctuation, and spoken submit.
2. Declarative replacements/snippets.
3. Language profiles and visible OSD language.
4. Separate raw/chat/email/code/notes shortcuts.
5. Local raw/processed history with paste-last and retry.
6. Optional local-LLM polish and semantic course correction.
7. Long-form mode with timer and limits.
8. Only then consider allowlisted, local context awareness.

## Sources

All product claims below come from Wispr's official site/help center or the
official Voxtype repository at the exact revision pinned by this flake.

[^flow-features]: [Wispr Flow official feature overview](https://try.wisprflow.ai/)
[^why-flow]: [Wispr Flow, “Why Flow”](https://wisprflow.ai/why-flow)
[^dictionary]: [Wispr Flow Help, “Teach Flow your words with the dictionary”](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary)
[^snippets]: [Wispr Flow Help, “Create and use snippets”](https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets)
[^context]: [Wispr Flow Help, “Context Awareness”](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness)
[^styles]: [Wispr Flow Help, “How to setup Flow Styles”](https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles)
[^whats-new]: [Wispr Flow official changelog](https://wisprflow.ai/whats-new)
[^long-dictation]: [Wispr Flow Help, “Longer dictation sessions”](https://docs.wisprflow.ai/articles/4841123325-longer-dictation-sessions-now-up-to-20-minutes)
[^hands-free]: [Wispr Flow Help, “Use Flow hands-free”](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free)
[^languages]: [Wispr Flow Help, “Use Flow with multiple languages”](https://docs.wisprflow.ai/articles/3191899797-use-flow-with-multiple-languages)
[^privacy]: [Wispr Flow Help, “Understanding Privacy Mode and Private Cloud Sync”](https://docs.wisprflow.ai/articles/4709791908-understanding-privacy-mode-and-cloud-sync)
[^scratchpad]: [Wispr Flow Help, “Using the Scratchpad to save and edit notes”](https://docs.wisprflow.ai/articles/9618237082-using-the-scratchpad-to-save-and-edit-notes)
[^voxtype-readme]: [Voxtype README at pinned revision](https://github.com/peteonrails/voxtype/blob/8d49248baa53f29cb33007c9625a37281c72e799/README.md)
[^voxtype-text]: [Voxtype text-processing configuration at pinned revision](https://github.com/peteonrails/voxtype/blob/8d49248baa53f29cb33007c9625a37281c72e799/docs/CONFIGURATION.md#text)
[^voxtype-post]: [Voxtype post-processing configuration at pinned revision](https://github.com/peteonrails/voxtype/blob/8d49248baa53f29cb33007c9625a37281c72e799/docs/CONFIGURATION.md#outputpost_process)
[^voxtype-profiles]: [Voxtype profiles configuration at pinned revision](https://github.com/peteonrails/voxtype/blob/8d49248baa53f29cb33007c9625a37281c72e799/docs/CONFIGURATION.md#profiles)
[^voxtype-cli]: [Voxtype CLI documentation at pinned revision](https://github.com/peteonrails/voxtype/blob/8d49248baa53f29cb33007c9625a37281c72e799/README.md#cli-options)
[^voxtype-meeting]: [Voxtype meeting mode at pinned revision](https://github.com/peteonrails/voxtype/blob/8d49248baa53f29cb33007c9625a37281c72e799/docs/MEETING_MODE.md)
