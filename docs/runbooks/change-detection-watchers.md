---
type: Runbook
title: Maintain page watchers
description: Add, validate, and troubleshoot declarative page watchers.
when: Read when adding, testing, deploying, or troubleshooting change-detection watchers.
resource: modules/aspects/services/automations.nix
tags: [runbook, automations, monitoring, change-detection]
---

# Maintain page watchers

Stable watchers are declared in
[automations.nix](../../modules/aspects/services/automations.nix).
The [implementation](../../modules/aspects/services/automations/change-detection.mjs)
polls pages and notifies Discord when an extracted value changes.

## Add or change a watcher

1. Choose a unique `slug` and readable label. Track a stable semantic value,
   such as a version, rather than surrounding page text or counters.
2. Inspect the actual response and add an entry using the existing module
   helpers. Use `fetcher = "curl"` when Node fetch gets a different response.
   Keep the notification link in `url` and a different fetch endpoint in `fetchUrl`.
3. For a custom extractor, include validation, display formatting, and fixtures
   for expected and malformed responses. Invalid content must fail extraction.
4. Run the [tests](../../modules/aspects/services/automations/change-detection.test.mjs):

   ```sh
   node --test modules/aspects/services/automations/change-detection.test.mjs
   ```

5. Use the [verification skill](../../.agents/skills/verify-nixos-config/SKILL.md)
   and normal [fleet deployment](fleet-operations.md). After activation, inspect:

   ```sh
   sudo systemctl start change-detection.service
   journalctl -u change-detection.service -n 100 --no-pager
   systemctl list-timers change-detection.timer
   ```

## Inspect overrides and state

`/home/containers/config/automations/change-watchers.json` must exist; use `[]`
when there are no overrides. Entries replace an entire default by `slug`.
To disable one:

```json
[{ "slug": "example-watcher", "enabled": false }]
```

State lives in `change-detection-state.json` beside that file. A new slug silently
establishes its baseline. Later changes notify; failed fetches or extraction
fail the run and can skip subsequent watchers. Check the journal and overrides
before changing patterns or baselines.

For delivery testing, use a controlled temporary watcher and remove its override
afterward. Narrow noisy patterns to the intended field. A wrong notification
link calls for correcting `url`, not replacing the fetch endpoint blindly.
