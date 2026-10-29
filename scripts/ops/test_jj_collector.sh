#!/usr/bin/env bash
# Real jj changes + real CLI, isolated from the study ledger.
set -euo pipefail
project=$(cd "$(dirname "$0")/../.." && pwd)
scratch=$(mktemp -d)
test_user="collector-test-$(uuidgen)"
trap 'rm -rf "$scratch" "$HOME/Library/Application Support/ContextSynapse/users/$test_user"' EXIT
export CONTEXT_SYNAPSE_HOME="$scratch/home"
export CONTEXT_SYNAPSE_BIN="$project/.build/debug/contextsynapse"
# CLI --user isolates tests; do not depend on HOME redirection on macOS.
cat > "$scratch/cli" <<SH
#!/bin/bash
exec "$CONTEXT_SYNAPSE_BIN" --user "$test_user" "\$@"
SH
# Keep one UUID for every invocation by writing it into the wrapper above.
chmod +x "$scratch/cli"
export CONTEXT_SYNAPSE_BIN="$scratch/cli"
# Capture calls as well, to assert retry count independently of ledger summaries.
mv "$scratch/cli" "$scratch/real-cli"
cat > "$scratch/cli" <<SH
#!/bin/bash
if [[ -f "$scratch/fail" ]]; then exit 4; fi
printf '%s\\n' "\$*" >> "$scratch/calls"
exec "$scratch/real-cli" "\$@"
SH
chmod +x "$scratch/cli"
jj git init --colocate "$scratch/repo" >/dev/null 2>&1
cd "$scratch/repo"
jj config set --repo user.name 'Collector test'
jj config set --repo user.email 'collector@example.invalid'
jj new >/dev/null 2>&1
collector="$project/scripts/collect-jj-events.sh"
bash "$collector" "$scratch/repo" "$scratch/state" --initialize
printf 'one\n' > example
jj commit -m 'controlled test' >/dev/null 2>&1
bash "$collector" "$scratch/repo" "$scratch/state"
bash "$collector" "$scratch/repo" "$scratch/state"
[[ $(wc -l < "$scratch/calls" | tr -d ' ') == 1 ]]
# Same change, rewritten commit: must not become a second observation.
jj describe @- -m 'rewritten test' >/dev/null 2>&1
bash "$collector" "$scratch/repo" "$scratch/state"
[[ $(wc -l < "$scratch/calls" | tr -d ' ') == 1 ]]
printf 'two\n' >> example
jj commit -m 'retry test' >/dev/null 2>&1
touch "$scratch/fail"
if bash "$collector" "$scratch/repo" "$scratch/state"; then exit 1; fi
rm "$scratch/fail"
bash "$collector" "$scratch/repo" "$scratch/state"
[[ $(wc -l < "$scratch/calls" | tr -d ' ') == 2 ]]
# Simulate a crash after append but before checkpoint: stable event ID prevents duplication.
sed '$d' "$scratch/state/seen" > "$scratch/seen"
cp "$scratch/seen" "$scratch/state/seen"
bash "$collector" "$scratch/repo" "$scratch/state"
"$scratch/real-cli" --events-summary | tee "$scratch/summary"
rg -q 'Events: 2 ' "$scratch/summary"
# Raw identifiers must not be persisted in the checkpoint.
[[ $(awk 'length != 64 {n++} END {print n+0}' "$scratch/state/seen") == 0 ]]
echo 'PASS: real jj collection, deduplication, rewrite, failure retry, checkpoint recovery'
