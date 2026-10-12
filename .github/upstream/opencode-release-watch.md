# OpenCode v2 release and pin readiness

`upstream-release-readiness.py` is an independent detector for the OpenCode v2
side-package migration (repository PR #222 pins 2.0.26 from Nixpkgs PR 569770;
alternate Nixpkgs PR 572946 packages the same release as `opencode_2`). It
registers as `opencode-v2` in `watchers.json`. The scheduled CI readiness sweep
calls it, and the publisher posts one readiness notice to issue #229. The
detector never mutates pins, timers, services, or the lock.

## Readiness rule

Readiness requires the _real_ upstream v2 package source (`anomalyco/opencode`)
at or after the tested `v2.0.26` tag — proven by exact tag-commit ancestry —
packaged by both:

1. the channel branch declared by the root `nixpkgs` input in `flake.nix`
   (currently `nixos-unstable`), and
2. the root `flake.lock` pin.

A merged Nixpkgs packaging PR alone never retires the overlay: the merge may be
missing from the branch, package an older source, or ship under an unexpected
attr. Candidate attrs are probed in order `opencode2`, `opencode_2`,
`opencode`; the highest packaged version wins. OpenCode's v2 tags currently
lack GitHub Release records, so this detector uses tested-tag source ancestry.
The separate T3 detector verifies stable GitHub Release metadata.

## Statuses

| Status              | Meaning                                                            |
| ------------------- | ------------------------------------------------------------------ |
| `waiting-upstream`  | tested tag untagged upstream, or no packaging PR merged            |
| `waiting-unstable`  | a packaging PR merged but the channel still lacks real v2          |
| `merged-not-pinned` | channel packages real v2, root pin does not                        |
| `PINNED-READY`      | channel and pin both package real v2 >= tested                     |
| `completed`         | overlay absent from the tree and the pin packages real v2          |
| `unavailable (...)` | transport, parser, or unknown-source failure — always fails closed |

`completed` describes the package workaround and pin only. Native builds and
fleet runtime verification remain separate requirements for closing #229.

## Usage

```sh
python3 .github/scripts/upstream-release-readiness.py --json   # structured metadata
python3 .github/scripts/upstream-release-readiness.test.py     # fixtures
```

Hosted CI installs `nh` from the checked-out Nixpkgs pin before the sweep.

`--json` prints `{"opencode-v2": {...}}` with the chosen attr, version, source
ref, and fetch origin for the channel and the pin, the tested-tag commit, the
flake branch, packaging PR state and branch reachability (via
`nh search prs`; the token comes from `gh auth token` through the environment
and is never printed or echoed), and overlay presence. Failures report only
the exception class, never raw transport output.
