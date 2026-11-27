"""Graph model: canonical form, delta, and apply.

A Graph is {"nodes": {id: attrs}, "edges": {edge_key: attrs}} where
edge_key is "src\\tkind\\tdst". Attribute values are JSON scalars, lists or
dicts. Every function here is pure.

The fold law the pipeline relies on (and verifies on every run):

    apply(project(parent), delta(project(parent), project(commit)))
        == project(commit)

so folding the deltas along a first-parent chain from the empty graph
reproduces the projection at its tip.
"""
from __future__ import annotations

import hashlib
import json
from typing import Any, Dict, List, Tuple

Graph = Dict[str, Dict[str, Dict[str, Any]]]
LOCATION_KEYS = ("loc",)


def empty() -> Graph:
    return {"nodes": {}, "edges": {}}


def edge_key(src: str, kind: str, dst: str) -> str:
    return src + "\t" + kind + "\t" + dst


def split_edge(key: str) -> Tuple[str, str, str]:
    src, kind, dst = key.split("\t")
    return src, kind, dst


def canonical(obj: Any) -> str:
    """Byte-stable JSON: sorted keys, fixed separators, no NaN, UTF-8 safe."""
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False,
                      allow_nan=False)


def digest(obj: Any) -> str:
    return hashlib.sha256(canonical(obj).encode("utf-8")).hexdigest()


def semantic(attrs: Dict[str, Any]) -> Dict[str, Any]:
    """Attributes minus location (line numbers move on unrelated edits)."""
    return {k: v for k, v in attrs.items() if k not in LOCATION_KEYS}


def delta(old: Graph, new: Graph) -> Dict[str, Any]:
    """Difference old -> new. Changed entries carry their full new attrs.

    nodes_changed is split into `semantic` (meaning changed) and `moved`
    (only location changed) for reporting; apply() treats both the same.
    """
    out: Dict[str, Any] = {
        "nodes_added": {}, "nodes_removed": [], "nodes_changed": {}, "nodes_moved": [],
        "edges_added": {}, "edges_removed": [], "edges_changed": {},
    }
    for nid in sorted(new["nodes"]):
        attrs = new["nodes"][nid]
        if nid not in old["nodes"]:
            out["nodes_added"][nid] = attrs
        elif old["nodes"][nid] != attrs:
            out["nodes_changed"][nid] = attrs
            if semantic(old["nodes"][nid]) == semantic(attrs):
                out["nodes_moved"].append(nid)
    out["nodes_removed"] = sorted(n for n in old["nodes"] if n not in new["nodes"])
    for key in sorted(new["edges"]):
        attrs = new["edges"][key]
        if key not in old["edges"]:
            out["edges_added"][key] = attrs
        elif old["edges"][key] != attrs:
            out["edges_changed"][key] = attrs
    out["edges_removed"] = sorted(k for k in old["edges"] if k not in new["edges"])
    return out


def apply(graph: Graph, change: Dict[str, Any]) -> Graph:
    """Return a new graph with `change` applied. Does not mutate inputs."""
    nodes = dict(graph["nodes"])
    edges = dict(graph["edges"])
    for nid in change["nodes_removed"]:
        nodes.pop(nid, None)
    nodes.update(change["nodes_added"])
    nodes.update(change["nodes_changed"])
    for key in change["edges_removed"]:
        edges.pop(key, None)
    edges.update(change["edges_added"])
    edges.update(change["edges_changed"])
    return {"nodes": nodes, "edges": edges}


def semantic_touched(change: Dict[str, Any]) -> List[str]:
    """Node ids whose meaning changed: added, removed, or semantically changed."""
    moved = set(change["nodes_moved"])
    ids = set(change["nodes_added"]) | set(change["nodes_removed"])
    ids |= {n for n in change["nodes_changed"] if n not in moved}
    return sorted(ids)


def is_empty(change: Dict[str, Any]) -> bool:
    return not any(change[k] for k in ("nodes_added", "nodes_removed", "nodes_changed",
                                       "edges_added", "edges_removed", "edges_changed"))
