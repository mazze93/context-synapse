#!/usr/bin/env python3
"""codegraph: fold a repo's git history into a code graph, dependency
matrices and an Obsidian vault.

Usage (from the repo root):
    python3 tools/codegraph/codegraph.py                 # HEAD -> codegraph-vault/
    python3 tools/codegraph/codegraph.py --rev v0.3.0 --out /tmp/vault-v030
    python3 tools/codegraph/codegraph.py --json-only     # print the HEAD graph digest

Deterministic: output is a pure function of the git objects reachable from
--rev, the config file, and GENERATOR. The working tree is never read.
Python 3.9+ standard library only; no network.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)  # our own package only; see README "Why sys.path"

from cgcore import config, fold, matrix, model, review, sbom, writer  # noqa: E402
from cgcore import vault_nodes, vault_pages  # noqa: E402

GENERATOR = "0.1.0"


def _repo_root(path: str) -> str:
    return subprocess.run(["git", "-C", path, "rev-parse", "--show-toplevel"], check=True,
                          capture_output=True, text=True).stdout.strip()


def generate(repo: str, rev: str, cfg: dict) -> tuple:
    """Return (files {rel: text}, meta, fold result). No side effects beyond
    reading git objects."""
    result = fold.run(repo, rev, cfg)
    graph, history = result["graph"], result["history"]
    names = vault_pages._names(graph, history)
    files = {}
    files.update(vault_nodes.render(graph, history))
    files.update(vault_pages.commit_notes(result["commits"], result["deltas"], names))
    files["Timeline.md"] = vault_pages.timeline(result["commits"], result["deltas"])
    for level in ("modules", "files", "types"):
        m = matrix.build(graph, level)
        files["Matrix - " + level + ".md"] = vault_pages.matrix_note(level, m, names)
        files["_data/matrix-" + level + ".csv"] = matrix.to_csv(m)
        files["_data/matrix-" + level + "-edges.csv"] = matrix.to_edge_csv(m)
    files["Review - Graph Findings.md"] = review.findings(graph, history, names, cfg)
    files["_data/graph.json"] = model.canonical(graph) + "\n"
    files["_data/sbom.cdx.json"] = model.canonical(sbom.build(graph, cfg["project"])) + "\n"
    files["_data/fold.json"] = model.canonical({
        "fold_law": result["fold_law"],
        "commits": [dict(c, delta_digest=model.digest(result["deltas"][c["sha"]]))
                    for c in result["commits"]]}) + "\n"
    meta = {"generator": GENERATOR, "adapter": result["adapter"], "head": result["head"],
            "config_digest": model.digest(config.fingerprint(cfg)),
            "graph_digest": result["fold_law"]["head_digest"],
            "title": (cfg["project"] or "Code") + " code graph", "fold_law": result["fold_law"]}
    files["00 Index.md"] = vault_pages.index(meta, graph, names)
    lowered = {}
    for rel in files:  # macOS volumes are case-insensitive by default
        if rel.lower() in lowered:
            raise RuntimeError("two notes collide on a case-insensitive disk: " + rel)
        lowered[rel.lower()] = rel
    return files, meta, result


def main(argv: list = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--repo", default=".", help="path inside the git repo (default: .)")
    parser.add_argument("--rev", default="HEAD", help="revision to fold up to (default: HEAD)")
    parser.add_argument("--config", default=os.path.join(HERE, "codegraph.config.json"))
    parser.add_argument("--out", help="output folder (default: <repo>/<config output_dir>)")
    parser.add_argument("--json-only", action="store_true",
                        help="print the graph digest and fold law; write nothing")
    args = parser.parse_args(argv)
    repo = _repo_root(args.repo)
    cfg = config.load(args.config)
    files, meta, result = generate(repo, args.rev, cfg)
    law = result["fold_law"]
    print("head", meta["head"][:12], "· nodes", len(result["graph"]["nodes"]),
          "· edges", len(result["graph"]["edges"]), "· commits", law["commits_checked"])
    print("fold law: per-commit", str(law["commits_ok"]) + "/" + str(law["commits_checked"]),
          "· mainline fold == head:", law["mainline_fold_equals_head"])
    print("graph digest", meta["graph_digest"])
    ok = law["commits_ok"] == law["commits_checked"] and law["mainline_fold_equals_head"]
    if args.json_only:
        return 0 if ok else 1
    out = args.out or os.path.join(repo, cfg["output_dir"])
    counts = writer.write_tree(out, files, {k: v for k, v in meta.items() if k != "fold_law"})
    print("vault", out, "· files", len(files), "· written", counts["written"],
          "· unchanged", counts["unchanged"], "· archived", counts["archived"])
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
