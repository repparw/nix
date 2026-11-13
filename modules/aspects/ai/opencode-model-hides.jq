# Compute the T3 Code opencode provider's hiddenModels from the models.dev
# catalog (the catalog OpenCode itself uses). Emits {hides, keeps}:
#   hides - model slugs to add to providerModelPreferences.opencode.hiddenModels
#   keeps - slugs to subtract first, so re-surfaced models survive
#
# Rules, per provider:
#   openrouter, huggingface, nvidia, google, mistral
#       Keep the latest model per family. A "-latest" alias wins over numbered
#       models in its family; otherwise the newest release_date wins (ties are
#       all kept, matching the server's isLegacy). Deprecated models and
#       non-latest numbered models are hidden. Models without a family are
#       kept. Paid models stay visible.
#   opencode (Zen), orcarouter
#       Free-inference providers: keep only zero-cost models, still subject to
#       the latest-per-family rule. Paid models are hidden.
#   groq, opencode-go
#       Dropped entirely: every model is hidden.
#   cloudflare-workers-ai
#       No latest-per-family rule. Only the eight paid-only models are hidden.
#
# nous-portal and explabs are plugin providers absent from models.dev; their
# plugins register only :free routes, so they need no entry here. One paid
# muse-ember is kept for API usage.

def free:
  (.cost == null) or ((.cost.input // 0) == 0 and (.cost.output // 0) == 0);

def deprecated: .status == "deprecated";

def blacklist:
  [ "@cf/moonshotai/kimi-k2.6"
  , "@cf/moonshotai/kimi-k2.7-code"
  , "@cf/zai-org/glm-5.2"
  , "@cf/zai-org/glm-5.3"
  , "@cf/zai-org/glm-5.3-flash"
  , "@cf/deepseek-ai/deepseek-v4-flash-0731"
  , "@cf/deepseek-ai/deepseek-v4.1-flash-1017"
  , "@cf/deepseek-ai/deepseek-v4-pro-0813"
  ];

# Split a provider's models object into keep/hide id lists using the
# per-family latest rule. Models with no family are kept unless deprecated.
def legacy_split:
  . as $models
  | ($models | to_entries | map(.value + { __id: .key })) as $all
  | ($all | map(select(((.family // "") == "") and (deprecated | not))) | map(.__id)) as $nofamily
  | ($all | map(select((.family // "") != "")) | group_by(.family) | map(
      . as $g
      | (map(select(.__id | endswith("-latest")))) as $alias
      | if ($alias | length) > 0 then
          $alias | map(select(deprecated | not) | .__id)
        else
          ($g | map(select(deprecated | not)) | map(.release_date // "")) as $dates
          | ($dates | max) as $newest
          | $g | map(select((deprecated | not) and ((.release_date // "") == $newest)) | .__id)
        end
    ) | add) as $family_keeps
  | ($nofamily + $family_keeps) as $keeps
  | { keeps: $keeps, hides: ($all | map(.__id) - $keeps) };

# Apply the free-only filter on top of the legacy split.
def free_only_split:
  . as $models
  | ($models | legacy_split) as $split
  | ($split.keeps | map(select($models[.] | free))) as $keeps
  | { keeps: $keeps, hides: ($split.hides + ($split.keeps - $keeps)) };

def result_for($id; $mode):
  .[$id].models as $models
  | if $mode == "drop" then
      { hides: ($models | keys | map($id + "/" + .)), keeps: [] }
    elif $mode == "blacklist" then
      { hides: [$models | keys[] | select(. as $k | blacklist | index($k)) | $id + "/" + .],
        keeps: [$models | keys[] | select((. as $k | blacklist | index($k)) | not) | $id + "/" + .] }
    elif $mode == "free" then
      ($models | free_only_split) as $r
      | { hides: ($r.hides | map($id + "/" + .)), keeps: ($r.keeps | map($id + "/" + .)) }
    else
      ($models | legacy_split) as $r
      | { hides: ($r.hides | map($id + "/" + .)), keeps: ($r.keeps | map($id + "/" + .)) }
    end;

. as $catalog
| {
    openrouter: "legacy",
    groq: "drop",
    huggingface: "legacy",
    "cloudflare-workers-ai": "blacklist",
    nvidia: "legacy",
    google: "legacy",
    mistral: "legacy",
    opencode: "free",
    orcarouter: "free",
    "opencode-go": "drop"
  } as $modes
| [ $modes | to_entries[]
    | .key as $id
    | .value as $mode
    | $catalog | result_for($id; $mode) ]
| { hides: (map(.hides) | add), keeps: (map(.keeps) | add) }
| .keeps += [ "opencode/muse-ember-1.0", "explabs/muse-ember" ]
| .hides = (.hides - .keeps)
