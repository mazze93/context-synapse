#!/usr/bin/env bash
#
# check_journal_append.sh — append-only guard for the decision log.
#
# Enforces the invariant that a lesson, once recorded, is never lost: every
# dated decision entry present at a BASELINE ref must still be present in the
# working copy — in EITHER the active log or the archive. This is what lets the
# log stay append-only (never delete a lesson) AND bounded (rotate old sprints
# into docs/journal/archive/ so the active file stays cheap to load). Moving an
# entry verbatim into the archive passes; deleting or editing it fails.
#
# To CORRECT a past decision, append a new dated reversal entry — do not edit the
# original in place. To BOUND size, move whole sprint sections into the archive.
#
# Usage:  check_journal_append.sh [baseline-ref]
#   baseline-ref defaults to HEAD^ (previous commit), or HEAD on a root commit.
#   CI passes origin/main (PRs) or the push's before-SHA.
#
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ACTIVE="docs/journal/DECISIONS.md"
ARCHIVE_DIR="docs/journal/archive"

BASE="${1:-}"
if [ -z "$BASE" ]; then
  if git rev-parse -q --verify 'HEAD^' >/dev/null 2>&1; then BASE="HEAD^"; else BASE="HEAD"; fi
fi

# Extract one normalized string per dated entry (unwraps multi-line bullets and
# collapses whitespace, so re-wrapping never reads as a change). An entry runs
# from a "- YYYY-MM-DD" bullet until the next dated bullet, ANY "#"-header, or a
# blank line — so following prose/headers never bleed into it. Callers extract
# each file separately, so file boundaries also terminate an entry cleanly.
extract() {
  awk '
    function norm(s){ gsub(/[[:space:]]+/," ",s); sub(/^ /,"",s); sub(/ $/,"",s); return s }
    function flush(){ if (e!="") { print norm(e); e="" } }
    /^- 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { flush(); e=$0; next }
    /^#/                                     { flush(); next }
    /^[[:space:]]*$/                         { flush(); next }
                                            { if (e!="") e = e " " $0 }
    END                                     { flush() }
  '
}

baseline_entries() {
  {
    git show "$BASE:$ACTIVE" 2>/dev/null | extract || true
    # NUL-delimit the archive paths: a filename with spaces (e.g.
    # "archive/Sprint One.md") would be word-split by `for f in $(...)`, so
    # `git show` failed on the fragments and — with the failure suppressed —
    # that file's decisions silently dropped out of the baseline, letting them
    # be deleted while the guard still passed (the P1 fixed here). Iterate the
    # same NUL-safe way working_entries already does, and do NOT suppress a
    # real `git show` failure: an unreadable baseline path must surface.
    while IFS= read -r -d '' f; do
      git show "$BASE:$f" | extract
    done < <(git ls-tree -rz --name-only "$BASE" -- "$ARCHIVE_DIR" 2>/dev/null)
  } | sort -u
}

working_entries() {
  {
    [ -f "$ACTIVE" ] && extract < "$ACTIVE"
    if [ -d "$ARCHIVE_DIR" ]; then
      find "$ARCHIVE_DIR" -type f -name '*.md' | while IFS= read -r f; do
        extract < "$f"
      done
    fi
  } | sort -u
}

missing="$(comm -23 <(baseline_entries) <(working_entries) || true)"

if [ -n "$missing" ]; then
  {
    echo "APPEND-ONLY VIOLATION — decision entries present at ${BASE} are missing from the working copy:"
    printf '%s\n' "$missing" | sed 's/^/  ✗ /'
    echo
    echo "The decision log is append-only. Never delete or edit an entry in place."
    echo "  · To bound size: MOVE whole sprint sections verbatim into ${ARCHIVE_DIR}/."
    echo "  · To correct a past call: APPEND a new dated reversal entry."
  } >&2
  exit 1
fi

echo "journal append-only: OK — no decision entries lost vs ${BASE}"
