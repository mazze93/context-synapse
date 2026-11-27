#!/usr/bin/env python3
"""Prove codegraph is deterministic and idempotent on this repository.

Checks (each prints PASS/FAIL; exit status 1 if any fail):
  1. hash-seed independence: three fresh runs under PYTHONHASHSEED=0,
     12345 and random produce byte-identical trees.
  2. idempotence: rerunning into an existing output writes nothing,
     archives nothing, and leaves every byte unchanged.
  3. clean copy: the generator as committed at HEAD (exported with
     `git archive`, so uncommitted edits cannot leak in) produces the same
     bytes as the working copy. Skipped if HEAD has no tools/codegraph.
  4. fold law: per-commit apply(parent, delta) == projection, and the
     mainline fold reproduces HEAD (read back from _data/fold.json).

Usage, from the repo root:
    python3 tools/codegraph/verify_determinism.py [--rev REV]
Writes only inside a temporary directory, which it removes at the end.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from typing import Dict, List

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "codegraph.py")


def tree_digest(root: str) -> Dict[str, str]:
    out = {}
    for base, _dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(base, name)
            with open(path, "rb") as handle:
                out[os.path.relpath(path, root)] = hashlib.sha256(handle.read()).hexdigest()
    return dict(sorted(out.items()))


def run(script: str, repo: str, rev: str, out: str, seed: str) -> str:
    env = dict(os.environ, PYTHONHASHSEED=seed)
    proc = subprocess.run([sys.executable, script, "--repo", repo, "--rev", rev, "--out", out],
                          capture_output=True, text=True, env=env)
    if proc.returncode != 0:
        raise SystemExit("codegraph failed:\n" + proc.stdout + proc.stderr)
    return proc.stdout


def diff(a: Dict[str, str], b: Dict[str, str]) -> List[str]:
    keys = sorted(set(a) | set(b))
    return [k for k in keys if a.get(k) != b.get(k)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rev", default="HEAD")
    args = parser.parse_args()
    repo = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                          text=True, check=True).stdout.strip()
    failures = 0

    def report(name: str, ok: bool, detail: str) -> None:
        nonlocal failures
        failures += 0 if ok else 1
        print(("PASS " if ok else "FAIL ") + name + " · " + detail)

    with tempfile.TemporaryDirectory(prefix="codegraph-verify-") as tmp:
        trees = {}
        for seed in ("0", "12345", "random"):
            out = os.path.join(tmp, "seed-" + seed)
            run(SCRIPT, repo, args.rev, out, seed)
            trees[seed] = tree_digest(out)
        bad = diff(trees["0"], trees["12345"]) + diff(trees["0"], trees["random"])
        report("hash-seed independence", not bad,
               str(len(trees["0"])) + " files identical across 3 seeds" if not bad
               else "differs: " + ", ".join(bad[:5]))

        first = os.path.join(tmp, "seed-0")
        stdout = run(SCRIPT, repo, args.rev, first, "0")
        after = tree_digest(first)
        quiet = "written 0 " in stdout and "archived 0" in stdout
        report("idempotence", quiet and after == trees["0"],
               stdout.strip().splitlines()[-1])

        clean = os.path.join(tmp, "clean")
        os.makedirs(clean)
        listed = subprocess.run(["git", "-C", repo, "ls-tree", "-r", "--name-only", "HEAD",
                                 "tools/codegraph/codegraph.py"], capture_output=True, text=True)
        if not listed.stdout.strip():
            print("SKIP clean copy · HEAD has no committed tools/codegraph yet")
        else:
            archive = subprocess.run(["git", "-C", repo, "archive", "HEAD", "tools/codegraph"],
                                     capture_output=True, check=True).stdout
            subprocess.run(["tar", "-x", "-C", clean], input=archive, check=True)
            out = os.path.join(tmp, "from-clean")
            run(os.path.join(clean, "tools", "codegraph", "codegraph.py"), repo, args.rev, out, "0")
            bad = diff(trees["0"], tree_digest(out))
            report("clean copy of committed generator", not bad,
                   "identical" if not bad else "differs: " + ", ".join(bad[:5])
                   + " (commit your generator changes, or this is a real leak)")

        with open(os.path.join(first, "_data", "fold.json"), encoding="utf-8") as handle:
            law = json.load(handle)["fold_law"]
        ok = law["commits_ok"] == law["commits_checked"] and law["mainline_fold_equals_head"]
        report("fold law", ok, str(law["commits_ok"]) + "/" + str(law["commits_checked"])
               + " commits · mainline fold of " + str(law["mainline_length"]) + " deltas == HEAD")
    print("OK" if failures == 0 else str(failures) + " check(s) failed")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
