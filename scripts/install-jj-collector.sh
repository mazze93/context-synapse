#!/usr/bin/env bash
# Install one opt-in macOS collector for this checkout. No repository discovery.
set -euo pipefail
umask 077
script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "${1:-$script_dir/..}" && pwd)
cli=${CONTEXT_SYNAPSE_BIN:-$repo/.build/release/contextsynapse}
jj_bin=$(command -v jj)
[[ -x "$cli" ]] || { echo 'Build the release CLI or set CONTEXT_SYNAPSE_BIN' >&2; exit 1; }
root="$HOME/Library/Application Support/ContextSynapse/instrument/jj-collector"
label=com.contextsynapse.jj-collector
plist="$HOME/Library/LaunchAgents/$label.plist"
[[ ! -e "$root" && ! -e "$plist" ]] || { echo 'Collector already installed; inspect before updating' >&2; exit 1; }
mkdir -p "$root" "$(dirname "$plist")"
cp "$script_dir/collect-jj-events.sh" "$root/collect.sh"
cp "$cli" "$root/contextsynapse"
chmod 700 "$root/collect.sh" "$root/contextsynapse"
CONTEXT_SYNAPSE_BIN="$root/contextsynapse" CONTEXT_SYNAPSE_JJ="$jj_bin" \
  bash "$root/collect.sh" "$repo" "$root/state" --initialize
python3 - "$plist" "$label" "$root" "$repo" "$jj_bin" <<'PY'
import plistlib,sys
plist,label,root,repo,jj=sys.argv[1:]
with open(plist,'wb') as f:
    plistlib.dump({'Label':label,'ProgramArguments':['/bin/bash',root+'/collect.sh',repo,root+'/state'],
        'EnvironmentVariables':{'CONTEXT_SYNAPSE_BIN':root+'/contextsynapse','CONTEXT_SYNAPSE_JJ':jj,
            'PATH':'/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin'},
        'StartInterval':60,'RunAtLoad':True,
        'StandardOutPath':root+'/stdout.log','StandardErrorPath':root+'/stderr.log'},f)
PY
plutil -lint "$plist"
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "Installed $label; polls finalized jj changes every 60 seconds"
echo "Stop: launchctl bootout gui/$(id -u) $plist"
