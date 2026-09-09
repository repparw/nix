---
type: Runbook
title: Add and Maintain Change-Detection Watchers
description: Define, test, deploy, and troubleshoot page watchers for the automation service.
when: Read when adding, testing, deploying, or troubleshooting change-detection watchers.
resource: modules/aspects/services/automations.nix
tags: [runbook, automations, monitoring, change-detection]
---

# Add and Maintain Change-Detection Watchers

The change-detection service polls configured pages, extracts a value, and
posts to the Discord webhook when that value changes. Stable watchers live as
declarative defaults in `modules/aspects/services/automations.nix` (see the
existing entries for the exact shape); the service implementation is beside it
in `modules/aspects/services/automations/`.

## Configuration layers

- The Nix module generates the default watcher file at build time — the source
  of truth for stable watchers.
- `/home/containers/config/automations/change-watchers.json` is a mutable
  local override for temporary changes or disabling a default without
  rebuilding. Keep it as `[]` when there are no overrides; the service
  requires the file to exist.

Watchers merge by `slug`: a runtime entry with the same slug replaces the
whole default entry (no deep merge). Disable a default with:

```json
[
  { "slug": "example-watcher", "enabled": false }
]
```

## Add a normal watcher

1. Choose a stable, unique `slug` and a human-readable `label`.
2. Track a stable semantic value (release/firmware version), not dates,
   counters, or surrounding page text — anything volatile pages you with
   noise.
3. Inspect the page with the same URL and request behavior the service will
   use, and add a `mkRegexWatcher` entry to `defaultWatchers`.
4. If the page needs curl's request behavior, set `fetcher = "curl"`;
   otherwise the default Node `fetch` transport applies.
5. If the fetch endpoint differs from the link users should open, set
   `fetchUrl` for fetching and keep `url` as the notification link.
6. Run the tests and deploy the configuration.

## Use a custom extractor

Reach for an extractor when a regex would be too fragile or one watcher must
produce a structured value. Add the watcher, the extractor implementation,
its validation entry, display formatting for object values, and fixtures for
expected plus malformed pages. Extractors fail closed — a bad page reports
nothing rather than a plausible wrong value.

## Notification and state behavior

State lives at
`/home/containers/config/automations/change-detection-state.json`. A new slug
establishes a baseline silently so adding a watcher never pages; later runs
notify only on value changes. Messages render `{{previous}}`,
`{{current}}`, and `{{url}}`. A failed fetch or extraction fails the run
instead of recording an invented value — check the service journal before
touching a pattern.

## Validate and deploy

From the repository root:

```sh
node --test modules/aspects/services/automations/change-detection.test.mjs
nix-instantiate --parse modules/aspects/services/automations.nix
git diff --check
nh os switch
```

After activation, run one check manually and inspect the result:

```sh
sudo systemctl start change-detection.service
journalctl -u change-detection.service -n 100 --no-pager
systemctl list-timers change-detection.timer
```

To test a notification safely, use a temporary watcher or a controlled local
override, then remove the override and restore the baseline afterward.

## Troubleshooting

- **HTTP 403 or different content:** compare Node and curl responses. Try
  `fetcher = "curl"`, add only the necessary headers, and use the actual
  download or detail URL rather than a canonical metadata page if those can
  diverge.
- **The watcher reports a change too often:** narrow the pattern to a stable
  version field. Do not track the whole page when only one release value
  matters.
- **The notification link is wrong:** keep the user-facing link in `url` and
  put only the machine-facing endpoint in `fetchUrl`.
- **A watcher is missing after activation:** check the runtime override file;
  a same-slug entry replaces the default, and `enabled: false` disables it.
- **The service stops before later watchers run:** inspect the journal. Runs
  are fail-fast, so one fetch or extraction error can skip the remaining
  watchers.

## Related source

- [Automation service definition](../../modules/aspects/services/automations.nix)
- [Change-detection implementation](../../modules/aspects/services/automations/change-detection.mjs)
- [Change-detection tests](../../modules/aspects/services/automations/change-detection.test.mjs)
- [Service model](../services/service-model.md)
