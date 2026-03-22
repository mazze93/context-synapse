#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "Building (debug)..."
cd "$ROOT"
swift build

BIN="$ROOT/.build/debug/context_synapse"
if [ ! -x "$BIN" ]; then
  echo "Binary not found at $BIN"
  exit 1
fi

echo "Baseline run..."
"$BIN" "Draft a project update" --app Mail >/dev/null

echo "Applying 30x positive feedback on intent=Create..."
for i in $(seq 1 30); do
  "$BIN" "noop" --intent Create --tone Concise --domain Work --feedback good >/dev/null
done

echo "Current Create prior + weight:"
python3 - <<'PY'
import json, os, pathlib
cfg = pathlib.Path(os.path.expanduser("~/Library/Application Support/ContextSynapse/config.json"))
d = json.loads(cfg.read_text())
p = d["priors"]["intents"]["Create"]
alpha, beta = p["alpha"], p["beta"]
prob = alpha/(alpha+beta)
w = d["intents"]["Create"]
print(f"Create prior: alpha={alpha} beta={beta} p={prob:.4f}")
print(f"Create weight: {w:.4f}")
PY

echo ""
echo "Applying 30x negative feedback on intent=Create..."
for i in $(seq 1 30); do
  "$BIN" "noop" --intent Create --tone Concise --domain Work --feedback bad >/dev/null
done

echo "Updated Create prior + weight:"
python3 - <<'PY'
import json, os, pathlib
cfg = pathlib.Path(os.path.expanduser("~/Library/Application Support/ContextSynapse/config.json"))
d = json.loads(cfg.read_text())
p = d["priors"]["intents"]["Create"]
alpha, beta = p["alpha"], p["beta"]
prob = alpha/(alpha+beta)
w = d["intents"]["Create"]
print(f"Create prior: alpha={alpha} beta={beta} p={prob:.4f}")
print(f"Create weight: {w:.4f}")
PY

echo ""
echo "Done."
