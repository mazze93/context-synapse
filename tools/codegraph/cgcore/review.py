"""Graph-grounded review queries. Pure; every finding cites graph nodes.

These are leads for a human or model reviewer, not verdicts: a function
with no caller may be called through a protocol or from outside the repo.
"""
from __future__ import annotations

from typing import Any, Dict, List, Set, Tuple

from . import matrix, model
from . import vault_names as vn


def _callers(graph: model.Graph) -> Dict[str, Set[str]]:
    inc: Dict[str, Set[str]] = {}
    for key in graph["edges"]:
        src, kind, dst = model.split_edge(key)
        if kind in ("calls", "instantiates"):
            inc.setdefault(dst, set()).add(src)
    return inc


def _reach(graph: model.Graph, roots: Set[str]) -> Set[str]:
    out: Dict[str, Set[str]] = {}
    for key in graph["edges"]:
        src, kind, dst = model.split_edge(key)
        if kind in ("calls", "instantiates"):
            out.setdefault(src, set()).add(dst)
    seen, stack = set(roots), sorted(roots)
    while stack:
        cur = stack.pop()
        for nxt in sorted(out.get(cur, ())):
            if nxt not in seen:
                seen.add(nxt)
                stack.append(nxt)
    return seen


def _sccs(labels: List[str], cells: Dict[Tuple[str, str], int]) -> List[List[str]]:
    """Tarjan's strongly connected components, deterministic order."""
    adj: Dict[str, List[str]] = {lab: [] for lab in labels}
    for (row, col) in sorted(cells):
        adj[row].append(col)
    index: Dict[str, int] = {}
    low: Dict[str, int] = {}
    stack: List[str] = []
    on: Set[str] = set()
    out: List[List[str]] = []
    counter = [0]

    def visit(v: str) -> None:
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on.add(v)
        for w in adj[v]:
            if w not in index:
                visit(w)
                low[v] = min(low[v], low[w])
            elif w in on:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop()
                on.discard(w)
                comp.append(w)
                if w == v:
                    break
            if len(comp) > 1:
                out.append(sorted(comp))

    for v in labels:
        if v not in index:
            visit(v)
    return sorted(out)


def findings(graph: model.Graph, history: Dict[str, Dict[str, Any]],
             names: Dict[str, Tuple[str, str]], cfg: Dict[str, Any]) -> str:
    nodes = graph["nodes"]
    lk = lambda nid: vn.link(*names[nid])  # noqa: E731
    test_mods = set(cfg["test_modules"])
    funcs = {n: a for n, a in nodes.items() if a["kind"] == "func"}
    callers = _callers(graph)
    lines = [vn.frontmatter({"codegraph": "review"}, ["codegraph", "codegraph/review"]),
             "# Review - Graph Findings", "",
             "Leads computed from the HEAD graph. Each is a query result, not a verdict.", ""]

    lines += ["## API probe sites", ""]
    for key in sorted(graph["edges"]):
        src, kind, dst = model.split_edge(key)
        if kind == "uses-api" and nodes.get(src, {}).get("module") not in test_mods:
            lines.append("- " + lk(dst) + " in " + lk(src) + " ×" + str(graph["edges"][key]["count"]))

    lines += ["", "## Private functions with no caller in the graph", ""]
    for nid in sorted(funcs):
        a = funcs[nid]
        if a["access"] in ("private", "fileprivate") and a["subkind"] == "func" and nid not in callers:
            lines.append("- " + lk(nid))

    lines += ["", "## Non-test functions no test reaches (direct or transitive calls)", ""]
    roots = {n for n, a in nodes.items() if a.get("module") in test_mods}
    reached = _reach(graph, roots)
    untested = [n for n, a in sorted(funcs.items())
                if a["module"] not in test_mods and not a["requirement"] and n not in reached]
    lines.append(str(len(untested)) + " of " + str(sum(1 for a in funcs.values()
                                                       if a["module"] not in test_mods))
                 + " non-test functions. Resolution is by name, so this undercounts reach through protocols and closures.")
    lines += ["- " + lk(n) for n in untested]

    for level in ("types", "files"):
        m = matrix.build(graph, level)
        lines += ["", "## Dependency cycles between " + level, ""]
        cycles = _sccs(m["labels"], m["cells"])
        lines += ["- " + " ↔ ".join(lk(n) for n in comp) for comp in cycles] or ["- none"]
        lines += ["", "## Highest fan-in " + level, ""]
        ranked = sorted(matrix.stats(m), key=lambda s: (-s[2], s[0]))[:10]
        lines += ["- " + lk(lab) + " · in " + str(fi) + " · out " + str(fo) for lab, fo, fi in ranked]

    lines += ["", "## Most-changed nodes across the fold", ""]
    churn = sorted(((h["changes"], n) for n, h in history.items() if n in nodes
                    and nodes[n]["kind"] in ("func", "type")), key=lambda x: (-x[0], x[1]))[:15]
    lines += ["- " + lk(n) + " · " + str(c) + " semantic changes" for c, n in churn]

    res: Dict[str, int] = {}
    for attrs in graph["edges"].values():
        res[attrs["resolution"]] = res.get(attrs["resolution"], 0) + attrs["count"]
    lines += ["", "## Resolution quality", ""]
    lines += ["- " + k + ": " + str(res[k]) + " sites" for k in sorted(res)]
    return "\n".join(lines) + "\n"
