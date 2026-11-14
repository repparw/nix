---
name: manage-page-watchers
description: Add, change, or troubleshoot web-page change detection in the fleet automations service, including value extraction, runtime overrides, saved baselines, and notifications.
---

# Manage page watchers

Use this skill for watchers that detect changes on HTTP pages. For upstream
dependency fixes and for retiring workarounds, use
[watch-upstream](../watch-upstream/SKILL.md).

## Edit and test a watcher

Start with the watcher helpers and `defaultWatchers` in
[automations.nix](../../../modules/aspects/services/automations.nix). Then read
the [implementation](../../../modules/aspects/services/automations/change-detection.mjs)
and its [tests](../../../modules/aspects/services/automations/change-detection.test.mjs).

Keep the slug of an existing watcher so its history stays useful. For a new
watcher, pick a unique slug and extract a stable value from the page, such as a
version number. Inspect the response using the watcher's real URL and transport.
Set `fetcher = "curl"` when Node fetch returns different content than curl.
Use only the arguments the helper supports. When the fetch URL and the
notification URL differ, use `fetchUrl` for extraction and `url` for the link
people open.

Give a custom extractor validation, display formatting, and test fixtures for
both expected and malformed responses. If the content is invalid, the extractor
must fail instead of returning a value it made up. Run the tests from the
repository root:

```sh
node --test modules/aspects/services/automations/change-detection.test.mjs
```

To check generated configuration and builds, use
[verify-fleet-change](../verify-fleet-change/SKILL.md). For authorized
activation and runtime checks, use
[fleet-operations](../fleet-operations/SKILL.md).

A live run of `change-detection.service` can post to Discord. Local fixtures do
not need a live notification. In an authorized live check, read the journal and
`change-detection.timer`, confirm the result is what you intended, and
afterward remove any temporary override you added to test delivery.

## Diagnose overrides and baselines

The file `/home/containers/config/automations/change-watchers.json` must exist.
With no overrides, it contains `[]`. An entry replaces the whole default that
has the same slug. To disable a default, add
`{"slug":"example-watcher","enabled":false}` to the override array.

The adjacent `change-detection-state.json` holds the baselines. A new slug sets
its baseline without notifying. Later value changes notify. A fetch or
extraction failure can stop the watchers that run after it. Before you change
patterns or state, inspect the response, the journal, and the overrides. Narrow
a noisy extraction to the field you care about. When you fix a URL or parser
failure, keep the existing baselines.

When you edit or diagnose `nixpkgs-security-fleet`, or interpret its alerts,
read the [security tracker reference](references/security-tracker.md).
