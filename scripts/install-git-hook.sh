#!/usr/bin/env bash
# =============================================================================
# install-git-hook.sh — Install the Context Synapse post-commit observer
# =============================================================================
# Installs scripts/hooks/post-commit into a target repository. Idempotent: safe
# to run repeatedly. If a post-commit hook already exists, it is preserved and
# chained rather than overwritten — clobbering someone's existing hook to
# install telemetry would be exactly the wrong trade.
#
# Usage:    bash scripts/install-git-hook.sh [TARGET_REPO]   (default: cwd)
#           bash scripts/install-git-hook.sh --uninstall [TARGET_REPO]
# Requires: git
# Platform: macOS ARM (M-series) + Linux compatible
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ── Constants ────────────────────────────────────────────────────────────────
readonly MARKER="context-synapse-observer"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOOK_SOURCE="${SCRIPT_DIR}/hooks/post-commit"

# ── Color helpers (skip formatting when not a TTY) ───────────────────────────
tty_bold=""  tty_reset=""  tty_green=""  tty_yellow=""  tty_red=""
if [ -t 1 ]; then
  tty_bold="\033[1m"; tty_reset="\033[0m"
  tty_green="\033[32m"; tty_yellow="\033[33m"; tty_red="\033[31m"
fi
info()    { printf "${tty_green}[INFO]${tty_reset}  %s\n" "$*"; }
warn()    { printf "${tty_yellow}[WARN]${tty_reset}  %s\n" "$*"; }
err()     { printf "${tty_red}[ERROR]${tty_reset} %s\n" "$*" >&2; }
die()     { err "$*"; exit 1; }
section() { printf "\n${tty_bold}▸ %s${tty_reset}\n" "$*"; }

# ── Pre-flight ───────────────────────────────────────────────────────────────
check_dependencies() {
  section "Checking dependencies"
  command -v git &>/dev/null || die "git not found"
  info "git: OK"
  [[ -f "$HOOK_SOURCE" ]] || die "Hook source missing: $HOOK_SOURCE"
  info "hook source: OK"
}

resolve_hooks_dir() {
  local target="$1"
  cd "$target" || die "Cannot enter: $target"
  git rev-parse --git-dir &>/dev/null || die "Not a git repository: $target"
  local git_dir
  git_dir=$(git rev-parse --git-dir)
  # --git-dir may be relative; resolve against the repo we just entered.
  ( cd "$git_dir" && pwd )
}

# ── Install ──────────────────────────────────────────────────────────────────
install_hook() {
  local hooks_dir="$1"
  local dest="${hooks_dir}/post-commit"
  local observer="${hooks_dir}/post-commit.d/${MARKER}"

  mkdir -p "${hooks_dir}/post-commit.d"
  cp "$HOOK_SOURCE" "$observer"
  chmod 755 "$observer"
  info "Observer installed: $observer"

  # Case 1: a hook exists and already chains us — nothing to do.
  if [[ -f "$dest" ]] && grep -q "$MARKER" "$dest" 2>/dev/null; then
    info "Dispatcher already present — skipping"
    return 0
  fi

  # Case 2: an unrelated hook exists — preserve it, then chain.
  if [[ -f "$dest" ]]; then
    local backup="${dest}.pre-${MARKER}"
    cp "$dest" "$backup"
    warn "Existing post-commit preserved at: $backup"
    {
      printf '\n# >>> %s >>>\n' "$MARKER"
      printf 'for _h in "$(dirname "$0")/post-commit.d/"*; do\n'
      printf '  [ -x "$_h" ] && "$_h" || true\n'
      printf 'done\n'
      printf '# <<< %s <<<\n' "$MARKER"
    } >> "$dest"
    chmod 755 "$dest"
    info "Chained observer onto existing hook"
    return 0
  fi

  # Case 3: no hook — write a minimal dispatcher.
  cat > "$dest" <<'DISPATCHER'
#!/usr/bin/env bash
# Dispatcher: runs every executable in post-commit.d/
# Observers must never fail a commit, so failures are swallowed.
set -uo pipefail
for _h in "$(dirname "$0")/post-commit.d/"*; do
  [ -x "$_h" ] && "$_h" || true
done
exit 0
DISPATCHER
  chmod 755 "$dest"
  info "Dispatcher created: $dest"
}

# ── Uninstall ────────────────────────────────────────────────────────────────
uninstall_hook() {
  local hooks_dir="$1"
  local observer="${hooks_dir}/post-commit.d/${MARKER}"

  if [[ -f "$observer" ]]; then
    rm -f "$observer"
    info "Observer removed: $observer"
  else
    info "No observer installed — nothing to remove"
  fi
  warn "Dispatcher left in place (it is harmless and may serve other hooks)"
  warn "Ledger data is NOT deleted. Remove manually if intended:"
  warn "  \"\${CONTEXT_SYNAPSE_HOME:-\$HOME/Library/Application Support/ContextSynapse}\""
}

# ── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
  local target="$1"
  section "Done"
  printf "${tty_bold}What was done:${tty_reset}\n"
  printf "  ✓ Observer installed into %s\n" "$target"
  printf "  ✓ Existing hooks preserved and chained\n"
  printf "\n${tty_bold}Next steps:${tty_reset}\n"
  printf "  1. Ensure 'contextsynapse' is on PATH, or export CONTEXT_SYNAPSE_BIN\n"
  printf "  2. Optionally label this repo's thread (use a codename, not a client):\n"
  printf "       echo 'my-thread-name' > .contextsynapse\n"
  printf "  3. Make a commit, then verify:\n"
  printf "       contextsynapse --events-summary\n"
  printf "  4. Read FALSIFICATION.md and commit your predictions BEFORE collecting\n\n"
}

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  local mode="install" target="."

  for arg in "$@"; do
    case "$arg" in
      --uninstall) mode="uninstall" ;;
      -h|--help)
        printf 'Usage: %s [--uninstall] [TARGET_REPO]\n' "$(basename "$0")"
        exit 0 ;;
      *) target="$arg" ;;
    esac
  done

  check_dependencies
  local hooks_dir
  hooks_dir="$(resolve_hooks_dir "$target")/hooks"
  mkdir -p "$hooks_dir"

  if [[ "$mode" == "uninstall" ]]; then
    section "Uninstalling"
    uninstall_hook "$hooks_dir"
  else
    section "Installing"
    install_hook "$hooks_dir"
    print_summary "$target"
  fi
}

main "$@"
