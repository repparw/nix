# OpenCode v2 release and pin readiness (standalone side-package detector)

`upstream-release-readiness.py` is an independent detector for the OpenCode v2
side-package migration (repository PR #222 pins 2.0.26 from Nixpkgs PR 569770;
alternate Nixpkgs PR 572946 packages the same release as `opencode_2`). It does
not register in `watchers.json`, is not called by `upstream-watch.sh`, and
never mutates pins, timers, services, or the lock.

## Readiness rule

Readiness requires the *real* upstream v2 package source (`anomalyco/opencode`)
at or after the tested `v2.0.26` tag — proven by exact tag-commit ancestry —
packaged by BOTH:

1. the channel branch declared by the root `nixpkgs` input in `flake.nix`
   (currently `nixos-unstable`), and
2. the root `flake.lock` pin.

A merged Nixpkgs packaging PR alone never retires the overlay: the merge may be
missing from the branch, package an older source, or ship under an unexpected
attr. Candidate attrs are probed in order `opencode2`, `opencode_2`,
`opencode`; the highest packaged version wins. Unlike the T3 Code nightly-v2
detector there is no stable-release gate: OpenCode v2 tags have no published
GitHub releases (`releases/latest` still points at v1).

## Statuses

| Status              | Meaning                                                                   |
| ------------------- | ------------------------------------------------------------------------- |
| `waiting-upstream`  | tested tag untagged upstream, or no packaging PR merged                   |
| `waiting-unstable`  | a packaging PR merged but the channel still lacks real v2                 |
| `merged-not-pinned` | channel packages real v2, root pin does not                                |
| `PINNED-READY`      | channel and pin both package real v2 >= tested                             |
| `completed`         | overlay absent from the tree and the pin packages real v2                  |
| `unavailable (...)` | transport, parser, or unknown-source failure — always fails closed         |

## Usage

```sh
python3 .github/scripts/upstream-release-readiness.py --json   # structured metadata
python3 .github/scripts/upstream-release-readiness.test.py     # fixtures
```

`--json` prints `{"opencode-v2": {...}}` with the chosen attr, version, source
ref, and fetch origin for the channel and the pin, the tested-tag commit, the
flake branch, packaging PR state and branch reachability (via
`nh search prs`; the token comes from `gh auth token` through the environment
and is never printed or echoed), and overlay presence. Failures report only
the exception class, never raw transport output.
