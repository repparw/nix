#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo 'usage: install.sh REPO [BIN_DIRECTORY]' >&2
  exit 2
fi
repo=$(realpath "$1")
bin=${2:-$HOME/.local/bin}
source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$bin"
bin=$(realpath "$bin")
version=$(cat "$source_dir/run.sh" "$source_dir/actions.sh" | sha256sum | cut -d ' ' -f1)
bundle="$bin/../lib/watch-upstream/$version"
mkdir -p "$bundle/previous"
install -m 644 "$source_dir/run.sh" "$source_dir/actions.sh" "$bundle/"
entries=$(jq -er '.gates | to_entries[] | [.key, .value.watcher] | @tsv' "$repo/data/upstream-gates.json")
while IFS=$'\t' read -r gate watcher; do
  [[ $gate =~ ^[a-z0-9][a-z0-9-]*$ && $watcher =~ ^watch-[a-z0-9-]+\.timer$ ]] || exit 2
  name=${watcher%.timer}.sh
  if [[ -f $bin/$name && ! -e $bundle/previous/$name ]]; then
    cp -p "$bin/$name" "$bundle/previous/$name"
  fi
  launcher=$(mktemp "$bin/.watch-upstream.XXXXXX")
  printf '#!/usr/bin/env bash\nexec bash %q "$@" %q %q\n' "$bundle/run.sh" "$repo" "$gate" > "$launcher"
  chmod 755 "$launcher"
  mv "$launcher" "$bin/$name"
  printf '%s -> %s\n' "$name" "$gate"
done <<< "$entries"
