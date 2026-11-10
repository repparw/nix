# Accepted security issues

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
