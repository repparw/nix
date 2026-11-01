# Diff the claimer's JSON databases against the previous notification state.
#
# Invocation (the claimer run script):
#   jq -n --argjson epic "<epic-games.json or {}>" \
#         --argjson gog "<gog.json or {}>" \
#         --argjson previous "<notify-state.json or {}>" \
#         -f claim-diff.jq
#
# Both databases share the shape { <user>: { <game>: {title, url, status} } }.
# Output:
#   { lines: [ "<emoji> <store>: <title> — <url>", ... ],  # new since previous
#     state: { "<store>|<user>|<id>": <status>, ... } }     # state to persist
def entries($store; $db):
  if ($db | type) == "object" then
    [
      $db
      | to_entries[]
      | .key as $user
      | .value
      | select(type == "object")
      | to_entries[]
      | {
          key: ($store + "|" + $user + "|" + .key),
          store: $store,
          title: (.value.title // .key),
          url: (.value.url // ""),
          status: (.value.status // "unknown"),
        }
    ]
  else [] end;

($previous // {}) as $previous
| ([entries("epic"; $epic // {})] + [entries("gog"; $gog // {})] | add // [])
| map(
    select(.status | type == "string")
    | select(
        .status == "claimed"
        or (.status != "existed"
          and .status != "manual"
          and .status != "skipped"
          and .status != "unknown"
          and .status != "requires base game")
      )
  )
| {
    lines:
      [
        .[]
        | select(.status != $previous[.key])
        | if .status == "claimed" then
          "✅ \(.store): \(.title) — \(.url)"
        else
          "⚠️ \(.store): \(.title) (\(.status)) — \(.url)"
        end
      ],
    state: (reduce .[] as $e ($previous; .[$e.key] = $e.status)),
  }
