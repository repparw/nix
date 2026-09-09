#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
usage: upstream-gates <validate|list|check> [GATE_ID]

check reports the first unsatisfied landing milestone:
  waiting-upstream  source release or PR is not ready
  waiting-unstable  upstream is ready, but the target branch is not
  waiting-pin       the target branch is ready, but flake.lock is behind
  adopting           the exact lock already contains the change
EOF
}

REGISTRY="${UPSTREAM_GATES_REGISTRY:-@REGISTRY@}"
REPO="${UPSTREAM_GATES_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOCKFILE="${UPSTREAM_GATES_LOCKFILE:-$REPO/flake.lock}"

die() {
  printf 'upstream-gates: %s\n' "$*" >&2
  exit 2
}

[[ -r "$REGISTRY" ]] || die "registry not readable: $REGISTRY"

api() {
  local endpoint=$1
  local -a args=( -fsSL --retry 2 --retry-delay 1 )
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    args+=( -H "Authorization: Bearer $GITHUB_TOKEN" )
  fi
  curl "${args[@]}" -H 'Accept: application/vnd.github+json' "https://api.github.com/$endpoint" 2>/dev/null
}

raw_file() {
  local repository=$1
  local ref=$2
  local path=$3
  curl -fsSL --retry 2 --retry-delay 1 "https://raw.githubusercontent.com/$repository/$ref/$path" 2>/dev/null
}

compare_contains() {
  local repository=$1
  local commit=$2
  local target=$3
  local response status

  if ! response=$(api "repos/$repository/compare/$commit...$target"); then
    DETAIL="compare failed: $repository $commit...$target"
    return 2
  fi
  status=$(jq -r '.status // empty' <<<"$response")
  if [[ $status == ahead || $status == identical ]]; then
    return 0
  fi
  DETAIL="$repository $target does not contain $commit (compare=$status)"
  return 1
}

version_at_least() {
  local actual=$1
  local minimum=$2
  [[ -n $actual && -n $minimum ]] || return 1
  [[ "$(printf '%s\n%s\n' "$minimum" "$actual" | sort -V | head -n1)" == "$minimum" ]]
}

package_version() {
  local repository=$1
  local ref=$2
  local path=$3
  local source

  if ! source=$(raw_file "$repository" "$ref" "$path"); then
    DETAIL="could not read $repository/$ref/$path"
    return 1
  fi
  awk -F'"' '/^[[:space:]]*version[[:space:]]*=[[:space:]]*"/{print $2; exit}' <<<"$source"
}

lock_revision() {
  local input=$1
  [[ -r "$LOCKFILE" ]] || die "lockfile not readable: $LOCKFILE"
  local node
  node=$(jq -r --arg input "$input" '.nodes.root.inputs[$input] // empty' "$LOCKFILE")
  [[ -n $node && $node != null ]] || die "input not found in lockfile: $input"
  jq -r --arg node "$node" '.nodes[$node].locked.rev // empty' "$LOCKFILE"
}

gate_json() {
  local id=$1
  jq -ce --arg id "$id" '.gates[$id] // error("unknown gate: " + $id)' "$REGISTRY"
}

validate_gate() {
  local id=$1
  local gate source_kind channel_kind pin_kind
  gate=$(gate_json "$id")
  for field in input repository branch source channel pin workaround completion watcher issue upstream; do
    jq -e --arg field "$field" 'has($field)' <<<"$gate" >/dev/null || die "$id: missing field $field"
  done
  source_kind=$(jq -r '.source.kind' <<<"$gate")
  channel_kind=$(jq -r '.channel.kind' <<<"$gate")
  pin_kind=$(jq -r '.pin.kind' <<<"$gate")
  case "$source_kind" in
    none|release|pull-request|pull-request-release|tag-contains-commits) ;;
    *) die "$id: unsupported source kind: $source_kind" ;;
  esac
  case "$channel_kind:$pin_kind" in
    package-version:package-version|package-release-version:package-release-version|package-tag-contains-commits:package-tag-contains-commits|file-contains:file-contains|commit-in-branch:commit-in-pin) ;;
    *) die "$id: unsupported channel/pin pair: $channel_kind/$pin_kind" ;;
  esac
}

validate_registry() {
  jq -e '.schema == 1 and (.gates | type == "object")' "$REGISTRY" >/dev/null \
    || die "registry must have schema 1 and an object of gates"
  while IFS= read -r id; do
    validate_gate "$id"
  done < <(jq -r '.gates | keys[]' "$REGISTRY")
}

SOURCE_MERGE_SHA=
SOURCE_RELEASE_VERSION=

check_source() {
  local gate=$1
  local kind repository tag response merged merged_at release_tag commit
  kind=$(jq -r '.source.kind' <<<"$gate")
  case "$kind" in
    none)
      return 0
      ;;
    release)
      repository=$(jq -r '.source.repository' <<<"$gate")
      tag=$(jq -r '.source.tag' <<<"$gate")
      if ! response=$(api "repos/$repository/releases/tags/$tag"); then
        DETAIL="release is not available: $repository $tag"
        return 1
      fi
      [[ $(jq -r '.draft // false' <<<"$response") != true ]] || {
        DETAIL="release is still a draft: $repository $tag"
        return 1
      }
      SOURCE_RELEASE_VERSION=${tag#v}
      return 0
      ;;
    pull-request|pull-request-release)
      repository=$(jq -r '.source.repository' <<<"$gate")
      local number
      number=$(jq -r '.source.number' <<<"$gate")
      if ! response=$(api "repos/$repository/pulls/$number"); then
        DETAIL="could not read pull request: $repository#$number"
        return 2
      fi
      merged=$(jq -r '.merged // false' <<<"$response")
      if [[ $merged != true ]]; then
        DETAIL="pull request is not merged: $repository#$number"
        return 1
      fi
      SOURCE_MERGE_SHA=$(jq -r '.merge_commit_sha // empty' <<<"$response")
      [[ -n $SOURCE_MERGE_SHA ]] || {
        DETAIL="merged pull request has no merge commit: $repository#$number"
        return 2
      }
      if [[ $kind == pull-request-release ]]; then
        merged_at=$(jq -r '.merged_at // empty' <<<"$response")
        if ! response=$(api "repos/$repository/releases?per_page=100"); then
          DETAIL="could not read releases: $repository"
          return 2
        fi
        release_tag=$(jq -r --arg merged_at "$merged_at" '[.[] | select(.draft != true and .published_at != null and .published_at > $merged_at)] | sort_by(.published_at) | .[0].tag_name // empty' <<<"$response")
        if [[ -z $release_tag ]]; then
          DETAIL="no release after PR merge: $repository#$number"
          return 1
        fi
        SOURCE_RELEASE_VERSION=${release_tag#v}
      fi
      return 0
      ;;
    tag-contains-commits)
      repository=$(jq -r '.source.repository' <<<"$gate")
      tag=$(jq -r '.source.tag' <<<"$gate")
      while IFS= read -r commit; do
        if compare_contains "$repository" "$commit" "$tag"; then
          :
        else
          local compare_rc=$?
          [[ $compare_rc -eq 2 ]] && return 2
          DETAIL="source tag $repository/$tag does not contain $commit"
          return 1
        fi
      done < <(jq -r '.source.commits[]' <<<"$gate")
      return 0
      ;;
    *)
      die "unsupported source kind: $kind"
      ;;
  esac
}

check_predicate() {
  local gate=$1
  local predicate=$2
  local ref=$3
  local kind repository path text actual minimum commit tag_prefix tag
  kind=$(jq -r '.kind' <<<"$predicate")
  case "$kind" in
    commit-in-branch)
      if compare_contains "$(jq -r '.repository' <<<"$gate")" "$SOURCE_MERGE_SHA" "$(jq -r '.branch' <<<"$gate")"; then
        :
      else
        local compare_rc=$?
        [[ $compare_rc -eq 2 ]] && return 2
        return 1
      fi
      ;;
    commit-in-pin)
      if compare_contains "$(jq -r '.repository' <<<"$gate")" "$SOURCE_MERGE_SHA" "$ref"; then
        :
      else
        local compare_rc=$?
        [[ $compare_rc -eq 2 ]] && return 2
        return 1
      fi
      ;;
    file-contains)
      repository=$(jq -r '.repository' <<<"$gate")
      path=$(jq -r '.path' <<<"$predicate")
      text=$(jq -r '.text' <<<"$predicate")
      local source
      if ! source=$(raw_file "$repository" "$ref" "$path"); then
        DETAIL="could not read $repository/$ref/$path"
        return 1
      fi
      if ! grep -Fq -- "$text" <<<"$source"; then
        DETAIL="$repository/$ref/$path does not contain: $text"
        return 1
      fi
      ;;
    package-version)
      repository=$(jq -r '.repository' <<<"$gate")
      path=$(jq -r '.path' <<<"$predicate")
      minimum=$(jq -r '.minimum' <<<"$predicate")
      if actual=$(package_version "$repository" "$ref" "$path"); then
        :
      else
        local version_rc=$?
        [[ $version_rc -eq 2 ]] && return 2
        return 1
      fi
      if ! version_at_least "$actual" "$minimum"; then
        DETAIL="$repository/$ref/$path provides ${actual:-unknown}; need >= $minimum"
        return 1
      fi
      ;;
    package-release-version)
      repository=$(jq -r '.repository' <<<"$gate")
      path=$(jq -r '.path' <<<"$predicate")
      if actual=$(package_version "$repository" "$ref" "$path"); then
        :
      else
        local version_rc=$?
        [[ $version_rc -eq 2 ]] && return 2
        return 1
      fi
      if ! version_at_least "$actual" "$SOURCE_RELEASE_VERSION"; then
        DETAIL="$repository/$ref/$path provides ${actual:-unknown}; need >= $SOURCE_RELEASE_VERSION"
        return 1
      fi
      ;;
    package-tag-contains-commits)
      repository=$(jq -r '.repository' <<<"$gate")
      path=$(jq -r '.path' <<<"$predicate")
      tag_prefix=$(jq -r '.tag_prefix' <<<"$predicate")
      if actual=$(package_version "$(jq -r '.repository' <<<"$gate")" "$ref" "$path"); then
        :
      else
        local version_rc=$?
        [[ $version_rc -eq 2 ]] && return 2
        return 1
      fi
      tag="$tag_prefix$actual"
      while IFS= read -r commit; do
        if compare_contains "$repository" "$commit" "$tag"; then
          :
        else
          local compare_rc=$?
          [[ $compare_rc -eq 2 ]] && return 2
          DETAIL="$repository/$tag does not contain $commit"
          return 1
        fi
      done < <(jq -r '.commits[]' <<<"$predicate")
      ;;
    *)
      die "unsupported predicate kind: $kind"
      ;;
  esac
  return 0
}

RESULT_STATUS=
RESULT_DETAIL=
RESULT_PIN=

check_gate() {
  local id=$1
  local gate input branch source_rc pin_rc
  gate=$(gate_json "$id")
  input=$(jq -r '.input' <<<"$gate")
  branch=$(jq -r '.branch' <<<"$gate")
  RESULT_PIN=$(lock_revision "$input")

  if check_source "$gate"; then
    :
  else
    source_rc=$?
    if [[ $source_rc -eq 2 ]]; then
      return 2
    fi
    RESULT_STATUS=waiting-upstream
    RESULT_DETAIL=${DETAIL:-source is not ready}
    return 0
  fi

  if check_predicate "$gate" "$(jq -c '.channel' <<<"$gate")" "$branch"; then
    :
  else
    pin_rc=$?
    if [[ $pin_rc -eq 2 ]]; then
      return 2
    fi
    RESULT_STATUS=waiting-unstable
    RESULT_DETAIL=${DETAIL:-channel predicate is not satisfied}
    return 0
  fi

  if check_predicate "$gate" "$(jq -c '.pin' <<<"$gate")" "$RESULT_PIN"; then
    :
  else
    pin_rc=$?
    if [[ $pin_rc -eq 2 ]]; then
      return 2
    fi
    RESULT_STATUS=waiting-pin
    RESULT_DETAIL=${DETAIL:-locked input predicate is not satisfied}
    return 0
  fi

  RESULT_STATUS=adopting
  RESULT_DETAIL="exact lock contains the upstream change"
  return 0
}

print_result() {
  local id=$1
  if [[ ${JSON_OUTPUT:-false} == true ]]; then
    jq -cn --arg id "$id" --arg status "$RESULT_STATUS" --arg detail "$RESULT_DETAIL" --arg pin "$RESULT_PIN" \
      '{id: $id, status: $status, detail: $detail, locked_revision: $pin}'
  else
    printf '%s\t%s\t%s\t%s\n' "$id" "$RESULT_STATUS" "$RESULT_PIN" "$RESULT_DETAIL"
  fi
}

validate_registry
command=${1:-check}
shift || true
JSON_OUTPUT=false
parsed_args=()
while [[ $# -gt 0 ]]; do
  if [[ $1 == --json ]]; then
    JSON_OUTPUT=true
  else
    parsed_args+=("$1")
  fi
  shift
done
set -- "${parsed_args[@]}"

case "$command" in
  validate)
    printf 'valid: %s\n' "$REGISTRY"
    ;;
  list)
    jq -r '.gates | keys[]' "$REGISTRY"
    ;;
  check)
    ids=()
    if [[ $# -gt 0 ]]; then
      ids=("$1")
      gate_json "$1" >/dev/null
    else
      mapfile -t ids < <(jq -r '.gates | keys[]' "$REGISTRY")
    fi
    errors=0
    for id in "${ids[@]}"; do
      if check_gate "$id"; then
        print_result "$id"
      else
        errors=$((errors + 1))
        printf '%s\terror\t%s\n' "$id" "${DETAIL:-check failed}" >&2
      fi
    done
    (( errors == 0 ))
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
