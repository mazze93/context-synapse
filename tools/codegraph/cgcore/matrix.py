"""Dependency matrices rolled up from the graph.

Pure. Three square matrices: types x types, files x files, modules x
modules. Cell (row, col) = number of use sites in `row` that depend on
`col` (sum of edge `count`). Structural edges (contains, declares,
extends) are excluded so a cell means "depends on", not "is inside".
Edges resolved as `ambiguous` are excluded and counted separately, so a
non-zero cell is never a guess.
"""
from __future__ import annotations

import csv
import io
from typing import Any, Dict, List, Optional, Tuple

from . import model

STRUCTURAL = {"contains", "declares", "extends", "built-from", "requires", "pins"}


def _type_of(nid: str, nodes: Dict[str, Dict[str, Any]]) -> Optional[str]:
    attrs = nodes.get(nid)
    if attrs is None:
        return None
    if attrs["kind"] == "type":
        return nid
    if attrs["kind"] == "func" and attrs["container"]:
        return attrs["container"]
    return None


def _file_of(nid: str, nodes: Dict[str, Dict[str, Any]]) -> Optional[str]:
    attrs = nodes.get(nid)
    if attrs is None:
        return None
    if attrs["kind"] == "file":
        return nid
    if attrs["kind"] in ("type", "func"):
        return "file:" + attrs["loc"]["file"]
    return None


def _module_of(nid: str, nodes: Dict[str, Dict[str, Any]]) -> Optional[str]:
    attrs = nodes.get(nid)
    if attrs is None:
        return None
    if attrs["kind"] in ("module", "dependency", "framework"):
        return nid
    if attrs["kind"] == "file":
        return "module:" + attrs["module"]
    if attrs["kind"] in ("type", "func"):
        return "module:" + attrs["module"]
    return None


_ROLLUPS = {"types": _type_of, "files": _file_of, "modules": _module_of}


def build(graph: model.Graph, level: str) -> Dict[str, Any]:
    """Return {labels, cells: {(row, col): count}, excluded_ambiguous}."""
    roll = _ROLLUPS[level]
    nodes = graph["nodes"]
    cells: Dict[Tuple[str, str], int] = {}
    excluded = 0
    for key in sorted(graph["edges"]):
        src, kind, dst = model.split_edge(key)
        if kind in STRUCTURAL:
            continue
        row, col = roll(src, nodes), roll(dst, nodes)
        if row is None or col is None or row == col:
            continue
        attrs = graph["edges"][key]
        if attrs["resolution"] == "ambiguous":
            excluded += attrs["count"]
            continue
        cells[(row, col)] = cells.get((row, col), 0) + attrs["count"]
    labels = sorted({n for n in nodes if roll(n, nodes) == n})
    return {"labels": labels, "cells": cells, "excluded_ambiguous": excluded}


def to_csv(m: Dict[str, Any]) -> str:
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow([""] + m["labels"])
    for row in m["labels"]:
        writer.writerow([row] + [m["cells"].get((row, col), 0) for col in m["labels"]])
    return buf.getvalue()


def to_edge_csv(m: Dict[str, Any]) -> str:
    """Sparse form: one line per non-zero cell; easier to diff and load."""
    buf = io.StringIO()
    writer = csv.writer(buf, lineterminator="\n")
    writer.writerow(["source", "target", "sites"])
    for (row, col) in sorted(m["cells"]):
        writer.writerow([row, col, m["cells"][(row, col)]])
    return buf.getvalue()


def stats(m: Dict[str, Any]) -> List[Tuple[str, int, int]]:
    """(label, fan_out, fan_in) per label: distinct non-zero columns/rows."""
    out = []
    for label in m["labels"]:
        fan_out = sum(1 for (r, _c) in m["cells"] if r == label)
        fan_in = sum(1 for (_r, c) in m["cells"] if c == label)
        out.append((label, fan_out, fan_in))
    return out
