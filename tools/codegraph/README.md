---
title: codegraph
version: 0.1.0
date: 2026-11-27
provenance: built for mazze93/context-synapse on branch feat/codegraph-review
tags: [codegraph, code-review, obsidian, determinism, fold]
---

# codegraph

Folds a repo's git history into a code graph, dependency matrices and an
Obsidian vault. Code change replays as a projection of a fold over the log:
each commit's graph is projected from its tree, diffed against its first
parent, and folding those deltas from the empty graph reproduces HEAD.

Python 3.9+ standard library only. No network. Reads git objects, never the
working tree, so output is a pure function of
`(git objects reachable from --rev, config, generator version)`.

## Run it

From the repo root (on Mazze's Mac: `~/Projects/cognitive/context-synapse`):

```zsh
python3 tools/codegraph/codegraph.py                       # HEAD -> ./codegraph-vault/
python3 tools/codegraph/verify_determinism.py              # prove it (seeds, rerun, clean copy, fold law)
python3 -m unittest discover -s tools/codegraph/tests -v   # unit + end-to-end tests
```

Open `codegraph-vault/` as an Obsidian vault, or copy it into an existing
vault. Start at `00 Index.md`. Nothing to commit afterwards: the vault is
gitignored (see below).

Options: `--rev <rev>` folds up to any commit or tag; `--out <dir>` writes
elsewhere; `--json-only` prints the graph digest and fold-law result and
writes nothing; `--config <file>` points at another config.

## What it writes

| Path | What |
|---|---|
| `00 Index.md` | counts, fold-law result, links to everything |
| `Timeline.md` | every commit in fold order with node/edge deltas |
| `Commits/Commit <sha12>.md` | one note per commit: added, removed, changed nodes and edges, against the first parent |
| `Types/`, `Functions/`, `Files/`, `Modules/`, `Products/`, `Package/`, `Frameworks/`, `Dependencies/`, `External/`, `API/` | one note per node at HEAD, YAML frontmatter (`kind`, `path`, `lines`, `first_commit`, `last_commit`, `semantic_changes`, tags) and `[[wikilinks]]` for every edge in and out |
| `Removed/` | nodes that existed in history but not at HEAD, from their last known projection |
| `Matrix - modules/files/types.md` | full dependency matrices with a legend |
| `Review - Graph Findings.md` | graph queries: API probe sites, uncalled private functions, code no test reaches, cycles, fan-in, churn, resolution quality |
| `_data/graph.json` | the HEAD graph, canonical JSON |
| `_data/fold.json` | fold-law result and every commit with its delta digest |
| `_data/matrix-*.csv` | dense and sparse (edge list) matrices |
| `_data/sbom.cdx.json` | CycloneDX 1.5 SBOM of external package dependencies |
| `.codegraph-manifest.json` | sha256 of every generated file, generator and adapter versions, HEAD, config digest; no timestamp |
| `.archive/` | earlier copies of any file a later run replaced or dropped |

## Guarantees and how they are checked

- **Deterministic.** Everything is sorted; no timestamps, no `hash()`, no
  set iteration order reaches output; git is called with a pinned locale
  and plumbing formats. `verify_determinism.py` runs under three
  `PYTHONHASHSEED` values and compares bytes. It was also run under
  Python 3.9.25 and 3.13 with byte-identical output.
- **Idempotent.** A rerun writes nothing and leaves mtimes alone
  (`written 0`). Verified by `verify_determinism.py`.
- **Clean-checkout equivalent.** `verify_determinism.py` exports the
  committed generator with `git archive` and checks it produces the same
  bytes, so uncommitted edits cannot leak into a result.
- **Fold law.** Every run checks `apply(parent, delta) == projection` for
  every commit and that the mainline fold equals HEAD; the CLI exits 1 if
  either fails.
- **Never destroys output.** The writer refuses a non-empty folder it did
  not create, and moves any file it would overwrite or drop into
  `.archive/<previous-head>-<manifest-digest>/` first.
- **Commit notes are immutable.** A commit note depends only on that commit
  and its first parent (it records `generation`, not a list position), so
  new history never rewrites an existing commit note.

## Why the vault is gitignored

A committed vault can never contain the commit that adds it: committing
the projection changes the log it is a projection of, so it would always
be one commit stale. It is also fully derivable (the determinism check is
the proof) and roughly 850 files. The repo keeps the generator, the
config and the tests; `.codegraph-manifest.json` and the graph digest in
`00 Index.md` let anyone confirm a vault matches a commit.

## Resolution and its limits

There is no type inference. Every edge records how it was resolved:
`exact` (a receiver, scope or type name pins it), `unique` (one visible
function fits the call's argument labels), or `ambiguous` (several fit; an
edge goes to each). Matrices leave ambiguous edges out and say how many.
Calls through a variable to a name in the adapter's ambient list (Swift
`append`, `write`, `update`, ...) are never classed `unique`. Local
functions and closures fold into their enclosing declaration; properties
count toward their type. These limits show up as missing or ambiguous
edges, never as crashes.

A function used as a value without parentheses, such as
`.map(EventLedger.csvEscape)`, gets no edge yet, so it can appear in the
review's "private functions with no caller" list. Treat that list as leads.

## Layout (adapter boundary)

```
codegraph.py              CLI: fold -> render -> write
verify_determinism.py     proof script
codegraph.config.json     everything repo-specific
cgcore/
  adapters/               the only language-aware code
    swift_lexer.py        Swift tokens
    swift_facts.py        Swift file -> neutral facts (contract in its docstring)
    swiftpm.py            Package.swift / Package.resolved -> neutral manifest facts
    __init__.py           registry: LANGUAGES, MANIFESTS, ADAPTER_VERSION
  build.py, resolve.py    neutral facts -> graph for one snapshot
  model.py                canonical JSON, delta, apply (the fold algebra)
  gitio.py                read-only git plumbing
  fold.py                 walk history, deltas, node history, fold-law check
  matrix.py, sbom.py      matrices and CycloneDX
  vault_*.py, review.py   Markdown rendering
  writer.py               the only module that writes files
tests/test_codegraph.py   14 tests incl. an end-to-end fold over a repo with a merge
```

To support another language, add an adapter that emits the same fact
shape and register it; nothing in `cgcore` outside `adapters/` changes.

## Why sys.path

The CLI prepends its own folder to `sys.path` so `import cgcore` finds this
package without installing anything. It never adds the current directory
or the repo being analysed, so a file in the analysed repo cannot shadow a
module.
