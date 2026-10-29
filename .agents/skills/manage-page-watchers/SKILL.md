---
name: manage-page-watchers
description: Add, modify, or troubleshoot web-page change detection in the fleet automations service, including extraction, runtime overrides, and notification state.
---

# Manage page watchers

Use this for HTTP page-change watchers. For upstream dependency fixes and
workaround retirement, use [watch-upstream](../watch-upstream/SKILL.md).

## Edit and validate

Read the watcher helpers and `defaultWatchers` in
[automations.nix](../../../modules/aspects/services/automations.nix), then the
relevant [implementation](../../../modules/aspects/services/automations/change-detection.mjs)
and [tests](../../../modules/aspects/services/automations/change-detection.test.mjs).

Preserve the slug of an existing watcher so its history remains useful. For a
new watcher, choose a unique slug and extract a stable semantic value such as
a version. Inspect the response using the watcher's actual URL and transport;
use `fetcher = "curl"` when Node fetch gets different content. Follow the helper's
supported arguments. When fetching and notification URLs differ, use `fetchUrl`
for extraction and `url` for the link people open.

Custom extractors need validation, display formatting, and fixtures for expected
and malformed responses. Invalid content must fail rather than invent a value.
Run the local tests from the repository root:

```sh
node --test modules/aspects/services/automations/change-detection.test.mjs
```

Use [verify-nixos-config](../verify-nixos-config/SKILL.md) for generated configuration
and builds, then [fleet-operations](../fleet-operations/SKILL.md) for authorized
activation and runtime verification. A live `change-detection.service` run can
post to Discord; local fixtures do not need a live notification. Within an
authorized live check, inspect its journal and `change-detection.timer`, confirm
the intended result, and remove any temporary delivery-test override afterward.

## Diagnose overrides and baselines

`/home/containers/config/automations/change-watchers.json` must exist; use `[]`
without overrides. An entry replaces the entire default with the same slug.
`{"slug":"example-watcher","enabled":false}` disables that default when placed
in the override array.

The adjacent `change-detection-state.json` holds baselines. A new slug establishes
its baseline silently; later value changes notify. Fetch or extraction failure
can stop later watchers. Inspect the response, journal, and overrides before
changing patterns or state. Narrow noisy extraction to the intended field;
preserve existing baselines when correcting a URL or parser failure.

## Accepted security issues

`nixpkgs-security-fleet` reads the public Nixpkgs tracker issues API with expanded
package mappings. Its `packages` list is a curated fleet watchlist, not an installed
closure inventory. Python package-set prefixes and selected versioned runtime
attributes are normalized before matching; titles are not searched for keywords.
The first run silently baselines the latest page. Later runs follow HTTPS pages
back to the previous issue checkpoint, notify once per CVE/package family, and
retain the checkpoint on fetch, schema, pagination, or delivery failure. A missing
checkpoint or more than 50 pages requires investigation rather than silently
skipping issues. This monitors newly created accepted issues, not later edits to
older issues or proof of a vulnerable deployed version. Check actual versions,
backported patches, and pinned inputs before treating a notification as exposure.
