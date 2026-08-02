---
type: Runbook
title: Add and Maintain Change-Detection Watchers
description: Define, test, deploy, and troubleshoot page watchers for the automation service.
when: Read when adding, testing, deploying, or troubleshooting change-detection watchers.
resource: modules/aspects/services/automations.nix
tags: [runbook, automations, monitoring, change-detection]
---

# Add and Maintain Change-Detection Watchers

The change-detection service polls configured pages, extracts a value, stores
the last value in state, and posts to the Discord webhook when that value
changes. The declarative defaults live in
`modules/aspects/services/automations.nix`; the implementation and tests live
beside it in `modules/aspects/services/automations/`.

## Configuration layers

There are two watcher files:

- The Nix module generates the default watcher file at build time. This is the
  source of truth for stable watchers.
- `/home/containers/config/automations/change-watchers.json` is a mutable local
  override file. It can be used for a temporary override or to disable a
  default without rebuilding.

Watchers are merged by `slug`. A runtime entry with the same slug replaces the
entire default entry; it is not a deep merge. To disable a default watcher,
use an entry such as:

```json
[
  { "slug": "example-watcher", "enabled": false }
]
```

Keep the runtime file as `[]` when there are no local overrides. The service
requires the file to exist, even when it is empty.

## Add a normal watcher

1. Choose a stable, unique `slug` and a human-readable `label`.
2. Inspect the page with the same URL and request behavior the service will
   use. Prefer a stable semantic value, such as a release or firmware
   version, over dates, counters, timestamps, or surrounding page text that
   changes for unrelated reasons.
3. Add a `mkRegexWatcher` entry to `defaultWatchers` in
   `modules/aspects/services/automations.nix`:

   ```nix
   (mkRegexWatcher {
     slug = "example-watcher";
     label = "Example release";
     url = "https://example.test/download";
     pattern = ''<span class="version">v([^<]+)</span>'';
     message = "Example release changed: {{previous}} -> {{current}}\n{{url}}";
   })
   ```

   The first capture group is used by default. Set `group` or `flags` in a
   raw watcher attribute set when the default helper is not sufficient.
4. If the page needs curl's request behavior, add `fetcher = "curl"`. The
   default transport is Node's `fetch`.
5. If the page to fetch differs from the link users should receive, set
   `fetchUrl` to the fetch endpoint and keep `url` as the useful notification
   link. `fetchUrl` affects fetching only; `{{url}}` always expands to `url`.
6. Run the tests and deploy the configuration.

Use a raw attribute set instead of `mkRegexWatcher` when a watcher needs
additional fields such as custom headers, a non-default timeout, a response
size limit, or a non-default capture group.

## Use a custom extractor

Use an extractor when a regular expression would be too fragile or when one
watcher needs to produce a structured value. The current implementation
whitelists extractor names deliberately.

1. Add the watcher with `mkExtractorWatcher` in
   `modules/aspects/services/automations.nix`.
2. Add the extractor implementation to
   `modules/aspects/services/automations/change-detection.mjs`.
3. Add the extractor name to the validation branch in `validateWatchers`.
4. Add display formatting in `displayValue` if the extracted value is an
   object.
5. Add fixtures for the expected HTML and for malformed or ambiguous pages in
   `change-detection.test.mjs`. The extractor should fail closed rather than
   report a plausible but incorrect value.

## Notification and state behavior

The state file is stored at
`/home/containers/config/automations/change-detection-state.json` and is
updated atomically. A new slug establishes a baseline and does not send a
notification. Later runs notify only when the extracted value changes.

The notification template supports:

- `{{previous}}` — the previous display value
- `{{current}}` — the current display value
- `{{url}}` — the watcher’s user-facing URL

If a fetch or extraction fails, the run fails rather than updating that
watcher with an invented value. Check the service journal before changing a
pattern.

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

The first successful run for a new watcher should show its current value and
create state without a Discord notification. To test a notification safely,
use a temporary watcher or a controlled local override, then remove the
override and restore the baseline afterward.

## Troubleshooting

- **HTTP 403 or different content:** compare Node and curl responses. Try
  `fetcher = "curl"`, add only the necessary headers, and use the actual
  download or detail URL rather than a canonical metadata page if those can
  diverge.
- **The watcher reports a change too often:** inspect the captured value and
  narrow the pattern to a stable version field. Do not track the whole page
  when only one release value matters.
- **The notification link is wrong:** keep the user-facing link in `url` and
  put only the machine-facing endpoint in `fetchUrl`.
- **A watcher is missing after activation:** check the runtime override file;
  an entry with the same slug replaces the default, and `enabled: false`
  disables it.
- **The service stops before later watchers run:** inspect the journal. The
  current run is fail-fast, so one fetch or extraction error can prevent the
  remaining watchers from being checked.

## Related source

- [Automation service definition](../../modules/aspects/services/automations.nix)
- [Change-detection implementation](../../modules/aspects/services/automations/change-detection.mjs)
- [Change-detection tests](../../modules/aspects/services/automations/change-detection.test.mjs)
- [Service model](../services/service-model.md)
