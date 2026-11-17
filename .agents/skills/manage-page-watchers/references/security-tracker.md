# Accepted security issues

The `nixpkgs-security-fleet` watcher reads the public Nixpkgs tracker issues
API, with expanded package mappings. Its `packages` list is a curated watchlist
for the fleet. It is not an inventory of the installed closure. Before matching,
the watcher normalizes Python package-set prefixes and selected versioned
runtime attributes. It does not search titles for keywords.

The first run sets a baseline from the latest page without notifying. Later runs
follow HTTPS pages back to the previous issue checkpoint and notify once for
each CVE and package family. The watcher keeps the checkpoint when a fetch,
schema, pagination, or delivery failure occurs. A missing checkpoint, or more
than 50 pages, needs investigation. Do not skip those issues silently.

The watcher monitors newly created accepted issues. It does not monitor later
edits to older issues, and it does not prove that a deployed version is
vulnerable. Before you treat a notification as exposure, check the actual
versions, backported patches, and pinned inputs.
