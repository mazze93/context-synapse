"""One Obsidian note per graph node (live at HEAD, or removed in history).

Pure: returns {relative path: note text}.
"""
from __future__ import annotations

from typing import Any, Dict, List, Tuple

from . import model
from . import vault_names as vn

INCOMING = {
    "calls": "called by", "references": "referenced by", "contains": "contained in",
    "declares": "declared in", "extends": "extended in", "conforms": "conformed to by",
    "imports": "imported by", "instantiates": "instantiated by", "uses-api": "used by",
    "depends-on": "depended on by", "built-from": "builds", "requires": "required by",
    "pins": "pinned by",
}
_MARK = {"exact": "", "unique": " · by selector", "ambiguous": " · ambiguous"}


def _adjacency(graph: model.Graph) -> Tuple[Dict[str, list], Dict[str, list]]:
    out: Dict[str, list] = {}
    inc: Dict[str, list] = {}
    for key in sorted(graph["edges"]):
        src, kind, dst = model.split_edge(key)
        attrs = graph["edges"][key]
        out.setdefault(src, []).append((kind, dst, attrs))
        inc.setdefault(dst, []).append((kind, src, attrs))
    return out, inc


def _edge_lines(entries: List[tuple], names: Dict[str, Tuple[str, str]], label_of) -> List[str]:
    lines: List[str] = []
    by_kind: Dict[str, List[tuple]] = {}
    for kind, other, attrs in entries:
        by_kind.setdefault(kind, []).append((other, attrs))
    for kind in sorted(by_kind):
        items = sorted(by_kind[kind], key=lambda x: x[0])
        lines.append("### " + label_of(kind) + " (" + str(len(items)) + ")")
        for other, attrs in items:
            name, label = names[other]
            count = " ×" + str(attrs["count"]) if attrs["count"] > 1 else ""
            lines.append("- " + vn.link(name, label) + count + _MARK[attrs["resolution"]])
        lines.append("")
    return lines


def _summary(nid: str, attrs: Dict[str, Any], names: Dict[str, Tuple[str, str]]) -> List[str]:
    lines = []
    loc = attrs.get("loc")
    if loc:
        fname = names.get("file:" + loc["file"], (loc["file"], ""))
        lines.append("Declared in " + vn.link(*fname) + " · lines " + str(loc["line"])
                     + "–" + str(loc["end_line"]))
    if attrs["kind"] == "func" and attrs["container"]:
        lines.append("Member of " + vn.link(*names[attrs["container"]]))
    if attrs["kind"] == "func" and attrs["requirement"]:
        lines.append("Requirement only (no body).")
    if attrs.get("external"):
        lines.append("Extension of a type not declared in this repo.")
    for key in ("requirement", "version", "revision", "location"):
        if attrs["kind"] == "dependency" and attrs.get(key):
            lines.append(key.capitalize() + ": `" + str(attrs[key]) + "`")
    return lines


def _fields(nid: str, attrs: Dict[str, Any], hist: Dict[str, Any], status: str) -> Dict[str, Any]:
    fields: Dict[str, Any] = {"codegraph": "node", "id": nid, "kind": attrs["kind"],
                              "status": status}
    for key in ("subkind", "module", "access", "digest", "selector", "qual", "path"):
        if attrs.get(key) not in (None, ""):
            fields[key] = attrs[key]
    if attrs.get("loc"):
        fields["path"] = attrs["loc"]["file"]
        fields["lines"] = str(attrs["loc"]["line"]) + "-" + str(attrs["loc"]["end_line"])
    if hist:
        fields["first_commit"] = hist["first_commit"][:12]
        fields["last_commit"] = hist["last_commit"][:12]
        fields["semantic_changes"] = hist["changes"]
        if hist.get("removed_in"):
            fields["removed_in"] = hist["removed_in"][:12]
    return fields


def _history_lines(hist: Dict[str, Any]) -> List[str]:
    if not hist:
        return []
    line = ("First seen " + vn.link(vn.commit_name(hist["first_commit"]))
            + " · last changed " + vn.link(vn.commit_name(hist["last_commit"]))
            + " · " + str(hist["changes"]) + " semantic change(s)")
    if hist.get("removed_in"):
        line += " · removed in " + vn.link(vn.commit_name(hist["removed_in"]))
    return [line]


def render(graph: model.Graph, history: Dict[str, Dict[str, Any]]) -> Dict[str, str]:
    nodes = dict(graph["nodes"])
    removed = {nid: h["attrs"] for nid, h in history.items()
               if nid not in nodes and "attrs" in h}
    every = dict(removed)
    every.update(nodes)
    names = {nid: (vn.note_name(nid, a), vn.short_label(nid, a)) for nid, a in every.items()}
    out_adj, in_adj = _adjacency(graph)
    notes: Dict[str, str] = {}
    for nid in sorted(every):
        attrs = every[nid]
        is_removed = nid in removed
        hist = history.get(nid, {})
        tags = ["codegraph", "codegraph/" + attrs["kind"], "status/" + ("removed" if is_removed else "live")]
        if attrs.get("module"):
            tags.append("module/" + vn.tag(attrs["module"]))
        if attrs.get("subkind"):
            tags.append("kind/" + vn.tag(attrs["subkind"]))
        body = [vn.frontmatter(_fields(nid, attrs, hist, "removed" if is_removed else "live"), tags),
                "# " + vn.short_label(nid, attrs), ""]
        body += _summary(nid, attrs, names) + _history_lines(hist) + [""]
        if is_removed:
            body.append("Not present at HEAD; attributes are the last known projection.")
            body.append("")
        else:
            body += ["## Outgoing", ""] + _edge_lines(out_adj.get(nid, []), names, lambda k: k)
            body += ["## Incoming", ""] + _edge_lines(in_adj.get(nid, []), names,
                                                      lambda k: INCOMING.get(k, k + " (in)"))
        path = vn.folder(attrs, is_removed) + "/" + names[nid][0] + ".md"
        notes[path] = "\n".join(body).rstrip("\n") + "\n"
    return notes
