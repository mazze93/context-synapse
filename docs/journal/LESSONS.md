# Lessons — distilled, portable, carry-forward

The compressed, generalized takeaways from this project's decision log. Unlike
`DECISIONS.md` (append-only, dated, raw — the full record) and its `archive/`
(rotated raw entries), this file is **curated and small**: the lessons that
should survive the end of this project and be grafted into the foundations of
the next. When a lesson here stops being project-specific, it graduates to the
workspace layer (`~/Projects` templates / global CLAUDE.md).

Each lesson cites the dated `DECISIONS.md` entry (or session) it was distilled
from, so the raw evidence is always one lookup away.

---

## Verification

- **A passing check only proves what it reaches.** N/N green says nothing about
  the boundary the test never names. Enumerate the untested boundary and probe
  it before claiming "done" / "safe" / "verified." (touchstone; every "Fixed" in
  the Known Issues table earned it this way.)
- **Verify against disk before acting on a plan.** Between sessions the world
  moves — a staged command sequence can go stale (GitButler removed, jj already
  installed). Re-check state before pasting a plan; a dead reference is a defect,
  not context.

## Version control & history

- **Commit AND push together the moment work is verified or liked.** Unpushed is
  one laptop away from gone — this cost the Edgar-toward-lighthouse landing scene
  (unrecoverable; confirmed absent from main, all branches, backup tags, stash,
  and all 89 GitButler oplog snapshots) and the original of the global CLAUDE.md.
- **Read the set-difference, not the diff direction.** `git diff A B` showing
  deletions means B is *behind* A, not that A lost B's work. Before closing or
  deleting a branch, run `git diff --diff-filter=A --name-only main <branch>` —
  files *genuinely unique* to the branch. (2026-08-18 reclaim audit: all four
  branches had 0 unique files.)
- **A close must carry its proof.** "No unique content" asserted without the
  set-difference is unfalsifiable and forces the next person to re-derive it.
  Put the proof table in the close note and the journal. (The salvage audit and
  PR #23 close taught this by omission.)
- **Prefer VCS that makes conflicts and rewrites first-class and reversible.**
  The failure mode you pick matters more than the happy path: GitButler blocked
  commits and left marker sludge in tracked files; jj makes conflicts
  non-blocking and every op undoable. (2026-08-18 pivot.)

## The journal itself

- **Separate the append-only log from the disposable pointer.** `DECISIONS.md`
  (lessons) only grows; `CHECKPOINT.md` (resume-here state) is *meant* to be
  rewritten. Conflating them makes the log look swept when it never was.
- **Append-only and bounded reconcile via rotate + distill, enforced not
  trusted.** Never delete a lesson; move old sprints to `archive/`; distill the
  generalized takeaway into this file. `scripts/ops/check_journal_append.sh`
  makes deletion/edit fail CI while allowing rotation — so preservation is
  provable, not a matter of discipline. (2026-08-18, this sprint.)

## This codebase

- **Duplicate types and abandoned file-splits resurface silently in merges.**
  `Prior`/`SynapticPrior` and the never-shipped DecayConstants split both bit
  here; check for reintroduced duplicates after any merge.
- **AI/on-device records carry host fingerprints — never route them to stdout or
  CI logs.** Public logs leak the fingerprint. Persist to Application Support
  only; enforce with a containment test. (2026-07-21, PR #24.)
