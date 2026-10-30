#!/usr/bin/env bash
# Poll finalized, locally authored jj changes. No network and no history replay.
# State holds salted hashes of change IDs, never raw commit IDs or messages.
set -euo pipefail
umask 077
repo=${1:?Usage: collect-jj-events.sh REPO STATE_DIR [--initialize]}
state=${2:?state directory required}
cd "$repo"
: "${CONTEXT_SYNAPSE_BIN:?Set an absolute path to the CLI}"
: "${CONTEXT_SYNAPSE_JJ:=jj}"
[[ -x "$CONTEXT_SYNAPSE_BIN" ]] || { echo 'Collector CLI unavailable' >&2; exit 1; }
mkdir -p "$state"
# launchd serializes its job; lock also protects manual invocations.
mkdir "$state/lock" 2>/dev/null || { echo 'Collector already running; check lock if prior run was killed' >&2; exit 1; }
trap 'rm -rf "$state/lock"' EXIT
salt_file="$state/salt"
if [[ ! -f "$salt_file" ]]; then
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$salt_file"
fi
salt=$(cat "$salt_file")
hash() { shasum -a 256 | cut -d' ' -f1; }
# No messages, filenames, branches or author identities enter these rows.
# Exclude the open working copy; a change becomes observable after jj commit/new.
rows=$("$CONTEXT_SYNAPSE_JJ" --ignore-working-copy --at-op @ log -r 'mine() ~ @ ~ (empty() & description(exact:""))' --no-graph \
  -T 'change_id ++ " " ++ commit_id ++ "\n"')
if [[ ${3:-} == --initialize ]]; then
  [[ ! -e "$state/seen" ]] || { echo 'Already initialized; baseline unchanged' >&2; exit 1; }
  while read -r change revision; do
    [[ -n "$change" ]] || continue
    printf '%s' "$salt:$change" | hash
  done <<< "$rows" > "$state/seen"
  echo 'Baseline initialized; historical changes excluded'
  exit 0
fi
[[ -f "$state/seen" ]] || { echo 'Initialize before collecting' >&2; exit 1; }
identity=$(git config --get remote.origin.url || git rev-parse --show-toplevel)
# Reuse the original per-install salt to retain the existing repo attribution.
instrument_home=${CONTEXT_SYNAPSE_HOME:-$HOME/Library/Application Support/ContextSynapse}
instrument_salt="$instrument_home/instrument/salt"
mkdir -p "$(dirname "$instrument_salt")"
if [[ ! -f "$instrument_salt" ]]; then
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$instrument_salt"
fi
repo_token=$(printf '%s' "$(cat "$instrument_salt"):$identity" | hash | cut -c1-16)
synapse="repo-$repo_token"
if [[ -f .contextsynapse ]]; then
  label=$(head -n 1 .contextsynapse | tr -d '\r\n' | tr -cd 'A-Za-z0-9._:-')
  [[ -z "$label" ]] || synapse=${label:0:128}
fi
# Oldest first; raw IDs remain in memory only.
ordered=$(printf '%s\n' "$rows" | awk '{a[NR]=$0} END {for(i=NR;i>0;i--) print a[i]}')
while read -r change revision; do
  [[ -n "$change" ]] || continue
  key=$(printf '%s' "$salt:$change" | hash)
  if grep -qxF "$key" "$state/seen"; then continue; fi
  event_id="${key:0:8}-${key:8:4}-${key:12:4}-${key:16:4}-${key:20:12}"
  at=$(git show -s --format=%cI "$revision")
  count=$(git diff-tree --root --no-commit-id --name-only -r -z "$revision" | tr -cd '\000' | wc -c | tr -d ' ')
  "$CONTEXT_SYNAPSE_BIN" --record git.commit --synapse "$synapse" \
    --repo-token "$repo_token" --changed-files "$count" --at "$at" --source jj-poll --event-id "$event_id"
  printf '%s\n' "$key" >> "$state/seen"
done <<< "$ordered"
date -u +%Y-%m-%dT%H:%M:%SZ > "$state/last-success"
