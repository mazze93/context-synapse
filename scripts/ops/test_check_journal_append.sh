#!/usr/bin/env bash
#
# test_check_journal_append.sh — regression harness for the append-only guard.
#
# Builds throwaway git repos under a temp root, mutates each working copy, and
# asserts check_journal_append.sh exits 0 (allowed) or 1 (violation). The guard
# compares the WORKING COPY against a baseline ref, so each case edits files on
# disk and passes the baseline SHA.
#
# Headline case `delete space-named archive file`: a dated decision in an
# archive file whose name contains a space ("Sprint One.md"). The pre-fix guard
# word-split that path in `for f in $(git ls-tree ...)`, dropped the file from
# the baseline set, and reported OK after the decision was deleted — the P1 from
# PR #28. This harness fails if that regression ever returns.
#
# SAFETY: an earlier version cd'd inside a `$(...)` command substitution, whose
# subshell cd did not persist — so its git commits landed in the real project
# repo. This version cd's in the parent shell and hard-asserts every case runs
# under TMPROOT and never at the real repo's toplevel before touching git.
#
set -euo pipefail

GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check_journal_append.sh"
[ -x "$GUARD" ] || { echo "guard not found/executable: $GUARD" >&2; exit 2; }

REAL_REPO="$(git -C "$(dirname "$GUARD")" rev-parse --show-toplevel)"
# Resolve symlinks (macOS /var → /private/var) so the under-TMPROOT safety
# assertion compares canonical paths against canonical `pwd -P`.
TMPROOT="$(cd "$(mktemp -d)" && pwd -P)"
trap 'cd /; rm -rf "$TMPROOT"' EXIT

pass=0 fail=0

# casedir <name> — cd (in THIS shell) into a fresh isolated git repo. Aborts
# hard if the resulting cwd is not under TMPROOT or is the real project repo.
casedir() {
  local d="$TMPROOT/$1"
  mkdir -p "$d"
  cd "$d"
  case "$(pwd -P)/" in
    "$TMPROOT"/*) : ;;
    *) echo "UNSAFE: cwd '$(pwd -P)' not under TMPROOT" >&2; exit 2 ;;
  esac
  git init -q
  [ "$(git rev-parse --show-toplevel)" != "$REAL_REPO" ] || {
    echo "UNSAFE: refusing to run inside the real repo $REAL_REPO" >&2; exit 2; }
  git config user.email t@t.t; git config user.name t
  mkdir -p docs/journal/archive
}

# seed_commit — commit the current working copy as the baseline; sets BASE.
seed_commit() { git add -A; git commit -qm baseline; BASE="$(git rev-parse HEAD)"; }

assert_exit() {
  local name="$1" want="$2"
  set +e; "$GUARD" "$BASE" >/dev/null 2>&1; local got=$?; set -e
  if [ "$got" = "$want" ]; then
    echo "  ✓ ${name} (exit ${got})"; pass=$((pass+1))
  else
    echo "  ✗ ${name}: expected ${want}, got ${got}"; fail=$((fail+1))
  fi
}

echo "append-only guard regression matrix:"

# 1. clean — baseline decision still present → OK
casedir clean
printf -- '- 2026-08-20 Adopt jj colocated workflow\n' > docs/journal/DECISIONS.md
seed_commit
assert_exit "clean (unchanged)" 0

# 2. delete-active — remove a dated decision from the active log → VIOLATION
casedir delete_active
printf -- '- 2026-08-20 Adopt jj colocated workflow\n- 2026-08-21 Freeze FALSIFICATION.md before data\n' > docs/journal/DECISIONS.md
seed_commit
printf -- '- 2026-08-20 Adopt jj colocated workflow\n' > docs/journal/DECISIONS.md
assert_exit "delete active entry" 1

# 3. rotate — move an entry verbatim from active into the archive → OK
casedir rotate
printf -- '- 2026-08-20 Adopt jj colocated workflow\n- 2026-08-21 Freeze FALSIFICATION.md before data\n' > docs/journal/DECISIONS.md
seed_commit
printf -- '- 2026-08-21 Freeze FALSIFICATION.md before data\n' > docs/journal/DECISIONS.md
printf -- '- 2026-08-20 Adopt jj colocated workflow\n' > docs/journal/archive/sprint-08.md
assert_exit "rotate to archive (verbatim)" 0

# 4. edit-in-place — alter a dated decision's text → VIOLATION
casedir edit
printf -- '- 2026-08-20 Adopt jj colocated workflow\n' > docs/journal/DECISIONS.md
seed_commit
printf -- '- 2026-08-20 Adopt gitbutler workflow\n' > docs/journal/DECISIONS.md
assert_exit "edit entry in place" 1

# 5. space-named archive DELETE — THE P1 REGRESSION → VIOLATION
casedir space_delete
echo placeholder > docs/journal/DECISIONS.md
printf -- '- 2026-08-19 Preserve the archived decision\n' > "docs/journal/archive/Sprint One.md"
seed_commit
rm "docs/journal/archive/Sprint One.md"
assert_exit "delete space-named archive file" 1

# 6. space-named archive INTACT → OK (guards against flagging whitespace wholesale)
casedir space_intact
echo placeholder > docs/journal/DECISIONS.md
printf -- '- 2026-08-19 Preserve the archived decision\n' > "docs/journal/archive/Sprint One.md"
seed_commit
assert_exit "space-named archive file intact" 0

echo
echo "passed ${pass}, failed ${fail}"
[ "$fail" = 0 ]
