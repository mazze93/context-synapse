"""Commit notes, timeline, matrices and the index. Pure."""
from __future__ import annotations

from typing import Any, Dict, List, Tuple

from . import matrix, model
from . import vault_names as vn


def _names(graph: model.Graph, history: Dict[str, Dict[str, Any]]) -> Dict[str, Tuple[str, str]]:
    every = {nid: h["attrs"] for nid, h in history.items() if "attrs" in h}
    every.update(graph["nodes"])
    return {nid: (vn.note_name(nid, a), vn.short_label(nid, a)) for nid, a in every.items()}


def _counts(change: Dict[str, Any]) -> Dict[str, int]:
    moved = len(change["nodes_moved"])
    return {"nodes_added": len(change["nodes_added"]), "nodes_removed": len(change["nodes_removed"]),
            "nodes_changed": len(change["nodes_changed"]) - moved, "nodes_moved": moved,
            "edges_added": len(change["edges_added"]), "edges_removed": len(change["edges_removed"]),
            "edges_changed": len(change["edges_changed"])}


def _edge_line(key: str, names: Dict[str, Tuple[str, str]]) -> str:
    src, kind, dst = model.split_edge(key)
    return "- " + vn.link(*names[src]) + " —" + kind + "→ " + vn.link(*names[dst])


def commit_notes(commits: List[Dict[str, Any]], deltas: Dict[str, Dict[str, Any]],
                 names: Dict[str, Tuple[str, str]]) -> Dict[str, str]:
    """One immutable note per commit: depends only on that commit and its
    first parent, so adding history never rewrites an existing commit note."""
    notes = {}
    for c in commits:
        sha = c["sha"]
        change = deltas[sha]
        counts = _counts(change)
        fields = {"codegraph": "commit", "sha": sha, "parents": c["parents"],
                  "generation": c["generation"], "date": c["date"], "subject": c["subject"]}
        fields.update(counts)
        body = [vn.frontmatter(fields, ["codegraph", "codegraph/commit"]),
                "# " + vn.text(c["subject"]), "",
                "`" + sha[:12] + "` · " + c["date"] + " · generation " + str(c["generation"])]
        if c["parents"]:
            body.append("Parents: " + " · ".join(vn.link(vn.commit_name(p)) for p in c["parents"])
                        + ("  (merge; delta is against the first parent)" if len(c["parents"]) > 1 else ""))
        else:
            body.append("Root commit; delta is against the empty graph.")
        body.append("")
        if model.is_empty(change):
            body.append("No change to the code graph.")
        else:
            body.append("Nodes +{nodes_added} −{nodes_removed} ~{nodes_changed} (moved only: {nodes_moved}) · "
                        "edges +{edges_added} −{edges_removed} ~{edges_changed}".format(**counts))
            moved = set(change["nodes_moved"])
            sections = [("Added", sorted(change["nodes_added"])),
                        ("Removed", change["nodes_removed"]),
                        ("Changed", sorted(n for n in change["nodes_changed"] if n not in moved))]
            for title, ids in sections:
                if ids:
                    body += ["", "## " + title + " nodes (" + str(len(ids)) + ")"]
                    body += ["- " + vn.link(*names[n]) for n in ids]
            for title, keys in (("added", sorted(change["edges_added"])),
                                ("removed", change["edges_removed"])):
                if keys:
                    body += ["", "## Edges " + title + " (" + str(len(keys)) + ")"]
                    body += [_edge_line(k, names) for k in keys]
        notes["Commits/" + vn.commit_name(sha) + ".md"] = "\n".join(body).rstrip("\n") + "\n"
    return notes


def timeline(commits: List[Dict[str, Any]], deltas: Dict[str, Dict[str, Any]]) -> str:
    rows = ["| # | commit | date | subject | +n | −n | ~n | +e | −e |",
            "|---|---|---|---|---|---|---|---|---|"]
    for i, c in enumerate(commits, 1):
        k = _counts(deltas[c["sha"]])
        rows.append("| {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
            i, vn.link(vn.commit_name(c["sha"]), c["sha"][:7]), c["date"][:10], vn.text(c["subject"]),
            k["nodes_added"], k["nodes_removed"], k["nodes_changed"], k["edges_added"], k["edges_removed"]))
    head = vn.frontmatter({"codegraph": "timeline", "commits": len(commits)}, ["codegraph"])
    intro = ("# Timeline\n\nThe fold, oldest first (git topo order). Replay a change by opening "
             "its commit note; each delta is against the commit's first parent, and folding the "
             "deltas along the first-parent chain reproduces the HEAD graph.\n\n")
    return head + intro + "\n".join(rows) + "\n"


def matrix_note(level: str, m: Dict[str, Any], names: Dict[str, Tuple[str, str]]) -> str:
    labels = m["labels"]
    width = len(str(len(labels)))
    code = {lab: level[0].upper() + str(i).zfill(width) for i, lab in enumerate(labels, 1)}
    lines = [vn.frontmatter({"codegraph": "matrix", "level": level, "size": len(labels),
                             "excluded_ambiguous_sites": m["excluded_ambiguous"]}, ["codegraph", "codegraph/matrix"]),
             "# Dependency matrix: " + level, "",
             "Row depends on column; a cell is the number of use sites. Structural edges are left out; "
             + str(m["excluded_ambiguous"]) + " ambiguous call sites are left out so no cell is a guess. "
             "Full data: `_data/matrix-" + level + ".csv` (dense) and `_data/matrix-" + level + "-edges.csv`.",
             "", "## Legend", ""]
    fan = {lab: (o, i) for lab, o, i in matrix.stats(m)}
    for lab in labels:
        lines.append("- `" + code[lab] + "` " + vn.link(*names[lab]) + " · out " + str(fan[lab][0])
                     + " · in " + str(fan[lab][1]))
    lines += ["", "## Matrix", "", "| | " + " | ".join(code[c] for c in labels) + " |",
              "|---|" + "---|" * len(labels)]
    for row in labels:
        cells = [str(m["cells"].get((row, col), "")) for col in labels]
        lines.append("| `" + code[row] + "` | " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def index(meta: Dict[str, Any], graph: model.Graph, names: Dict[str, Tuple[str, str]]) -> str:
    kinds: Dict[str, int] = {}
    for attrs in graph["nodes"].values():
        kinds[attrs["kind"]] = kinds.get(attrs["kind"], 0) + 1
    law = meta["fold_law"]
    lines = [vn.frontmatter({"codegraph": "index", "head": meta["head"], "generator": meta["generator"],
                             "adapter": meta["adapter"], "nodes": len(graph["nodes"]),
                             "edges": len(graph["edges"]), "commits": law["commits_checked"],
                             "graph_digest": law["head_digest"]}, ["codegraph"]),
             "# " + meta["title"], "",
             "Generated by codegraph " + meta["generator"] + " from `" + meta["head"][:12]
             + "`. Every note is a pure function of the git objects, the config and the generator "
             "version; rerunning changes nothing.", "",
             "## Fold law", "",
             "- apply(parent, delta) == projection on " + str(law["commits_ok"]) + " of "
             + str(law["commits_checked"]) + " commits",
             "- folding " + str(law["mainline_length"]) + " first-parent deltas from empty reproduces HEAD: "
             + ("yes" if law["mainline_fold_equals_head"] else "NO"), "",
             "## Start here", "",
             "- [[Timeline]] · [[Review - Graph Findings]]",
             "- [[Matrix - modules]] · [[Matrix - files]] · [[Matrix - types]]", "",
             "## Counts", ""]
    lines += ["- " + k + ": " + str(kinds[k]) for k in sorted(kinds)]
    lines += ["", "## Modules", ""]
    lines += ["- " + vn.link(*names[n]) for n in sorted(graph["nodes"])
              if graph["nodes"][n]["kind"] in ("package", "product", "module", "dependency", "framework")]
    return "\n".join(lines) + "\n"
