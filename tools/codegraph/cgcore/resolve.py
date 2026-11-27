"""Symbol table and name resolution for one snapshot.

Pure. Resolution is name-based (no type inference), so every resolved edge
carries how it was resolved:
  exact          receiver or scope pins the target, or a type name matched
  unique         no scope, but exactly one visible function fits the call
  ambiguous      several visible functions fit; an edge goes to each
Callers that need precision (the matrices) skip `ambiguous`.
"""
from __future__ import annotations

import hashlib
from typing import Dict, Iterator, List, Optional, Tuple

RESOLUTION_RANK = {"exact": 0, "unique": 1, "ambiguous": 2}


def _combine(digests: List[str]) -> str:
    return hashlib.sha256("\x1f".join(sorted(digests)).encode()).hexdigest()[:16]


def compatible(params: List[dict], labels: List[str], trailing: bool) -> bool:
    """Can a call with these argument labels bind to these parameters?"""
    ptr = 0
    for param in params:
        if ptr < len(labels) and labels[ptr] == param["label"]:
            ptr += 1
        elif param["default"]:
            continue
        elif trailing and ptr == len(labels) and param["closure"]:
            continue
        else:
            return False
    return ptr == len(labels)


class Symbols:
    """Types and functions declared in a snapshot, plus lookup tables."""

    def __init__(self, files: List[Tuple[str, dict]], modules: Dict[str, str],
                 ambient: Tuple[str, ...] = ()) -> None:
        self.modules = modules
        self.ambient = set(ambient)
        self.nodes: Dict[str, dict] = {}
        self.structure_edges: List[Tuple[str, str, str]] = []
        self.by_qual: Dict[Tuple[str, str], str] = {}
        self.by_simple: Dict[str, List[str]] = {}
        self.keymap: Dict[Tuple[str, str], str] = {}
        self.funcs_by_name: Dict[str, List[str]] = {}
        self.inits: Dict[str, List[str]] = {}
        self.inherits: List[Tuple[str, str, str]] = []  # (path, type id, name)
        self.visible: Dict[str, List[str]] = {}
        self._digests: Dict[str, List[str]] = {}
        names = set(modules.values())
        for path, facts in files:
            own = modules[path]
            imported = sorted({i["module"] for i in facts["imports"] if i["module"] in names} - {own})
            self.visible[path] = [own] + imported
        for path, facts in files:
            self._types(path, facts, extensions=False)
        for path, facts in files:
            self._types(path, facts, extensions=True)
        for path, facts in files:
            self._funcs(path, facts)
        for nid, digests in self._digests.items():
            self.nodes[nid]["digest"] = _combine(digests)
        for name in self.by_simple:
            self.by_simple[name].sort()
        for name in self.funcs_by_name:
            self.funcs_by_name[name].sort()

    # ── lookups ───────────────────────────────────────────────────────────
    def type_named(self, qual: str, path: str) -> Optional[str]:
        for mod in self.visible[path]:
            hit = self.by_qual.get((mod, qual))
            if hit:
                return hit
        last = qual.split(".")[-1]
        cands = [t for t in self.by_simple.get(last, []) if self.nodes[t]["module"] in self.visible[path]]
        return cands[0] if len(cands) == 1 else None

    def types_simple(self, name: str, path: str) -> List[str]:
        """Candidates for a bare type name, nearest visibility tier first."""
        for mod in self.visible[path]:
            tier = [t for t in self.by_simple.get(name, []) if self.nodes[t]["module"] == mod]
            if tier:
                return tier
        return []

    # ── declaration passes ────────────────────────────────────────────────
    def _register_type(self, tid: str, attrs: dict, path: str, digest: str) -> None:
        if tid not in self.nodes:
            self.nodes[tid] = attrs
            self.by_qual[(attrs["module"], attrs["qual"])] = tid
            self.by_simple.setdefault(attrs["name"], []).append(tid)
        node = self.nodes[tid]
        if path not in node["files"]:
            node["files"] = sorted(node["files"] + [path])
        self._digests.setdefault(tid, []).append(digest)

    def _types(self, path: str, facts: dict, extensions: bool) -> None:
        mod = self.modules[path]
        fid = "file:" + path
        for d in facts["decls"]:
            if d["kind"] != "type" or d["extension"] != extensions:
                continue
            qual = d["key"][len("type:"):]
            if extensions:
                tid = self.type_named(qual, path)
                if tid is None:
                    tid = "type:" + mod + "." + qual
                    self._register_type(tid, self._type_attrs(d, mod, qual, path, external=True), path, d["digest"])
                else:
                    self._register_type(tid, self.nodes[tid], path, d["digest"])
                self.structure_edges.append((fid, "extends", tid))
            else:
                tid = "type:" + mod + "." + qual
                self._register_type(tid, self._type_attrs(d, mod, qual, path, external=False), path, d["digest"])
                parent = self.by_qual.get((mod, d["container"])) if d["container"] else None
                self.structure_edges.append((parent or fid, "contains", tid))
                if parent:
                    self.structure_edges.append((fid, "declares", tid))
            self.keymap[(path, d["key"])] = tid
            for name in d["inherits"]:
                self.inherits.append((path, tid, name))

    @staticmethod
    def _type_attrs(d: dict, mod: str, qual: str, path: str, external: bool) -> dict:
        return {"kind": "type", "subkind": d["subkind"], "name": qual.split(".")[-1], "qual": qual,
                "module": mod, "access": d["access"], "external": external, "files": [],
                "loc": {"file": path, "line": d["line"], "end_line": d["end_line"]}}

    def _funcs(self, path: str, facts: dict) -> None:
        mod = self.modules[path]
        for d in facts["decls"]:
            if d["kind"] != "func":
                continue
            container = self.type_named(d["container"], path) if d["container"] else None
            if d["container"] and container is None:
                container = "type:" + mod + "." + d["container"]
                if container not in self.nodes:
                    stub = dict(d, subkind="extension", line=d["line"], end_line=d["line"])
                    self._register_type(container, self._type_attrs(stub, mod, d["container"], path, True),
                                        path, "")
            qual = self.nodes[container]["qual"] + "." if container else ""
            owner_mod = self.nodes[container]["module"] if container else mod
            fnid = "func:" + owner_mod + "." + qual + d["selector"]
            if fnid not in self.nodes:
                self.nodes[fnid] = {
                    "kind": "func", "subkind": d["subkind"], "name": d["name"],
                    "selector": d["selector"], "module": owner_mod, "container": container or "",
                    "access": d["access"], "static": d["static"], "requirement": d["requirement"],
                    "params": d["params"], "file": path,
                    "loc": {"file": path, "line": d["line"], "end_line": d["end_line"]}}
                self.funcs_by_name.setdefault(d["name"], []).append(fnid)
                if d["name"] == "init" and container:
                    self.inits.setdefault(container, []).append(fnid)
                self.structure_edges.append((container or "file:" + path, "contains", fnid))
                if container:
                    self.structure_edges.append(("file:" + path, "declares", fnid))
            self._digests.setdefault(fnid, []).append(d["digest"])
            self.keymap[(path, d["key"])] = fnid


def _call_targets(sym: Symbols, path: str, owner: str, use: dict) -> Tuple[List[str], str]:
    name, labels, trailing, receiver = use["name"], use["labels"], use["trailing"], use["receiver"]
    owner_type = owner if owner.startswith("type:") else sym.nodes.get(owner, {}).get("container", "")
    if name[:1].isupper() and receiver is None:
        types = sym.types_simple(name, path)
        if len(types) != 1:
            return [], "exact"
        inits = [f for f in sym.inits.get(types[0], [])
                 if compatible(sym.nodes[f]["params"], labels, trailing)]
        return (inits, "exact") if len(inits) == 1 else (types, "exact")
    scope: Optional[str] = None
    if receiver in ("self", "Self"):
        scope = owner_type or None
    elif receiver and receiver[:1].isupper():
        scope = sym.type_named(receiver, path)
        if scope is None:
            return [], "exact"
    cands = [f for f in sym.funcs_by_name.get(name, [])
             if sym.nodes[f]["module"] in sym.visible[path]
             and compatible(sym.nodes[f]["params"], labels, trailing)]
    if scope:
        return [f for f in cands if sym.nodes[f]["container"] == scope], "exact"
    if receiver is None:
        for tier in ([f for f in cands if owner_type and sym.nodes[f]["container"] == owner_type],
                     [f for f in cands if not sym.nodes[f]["container"]]):
            if tier:
                return tier, "exact" if len(tier) == 1 else "ambiguous"
    if len(cands) == 1 and name not in sym.ambient:
        return cands, "unique"
    return cands, "ambiguous"


def use_edges(files: List[Tuple[str, dict]], modules: Dict[str, str],
              sym: Symbols) -> Iterator[Tuple[str, str, str, str]]:
    """Yield (src, kind, dst, resolution) for every resolvable use."""
    for path, tid, name in sym.inherits:
        hit = sym.type_named(name, path)
        yield tid, "conforms", hit or "extern:" + name, "exact"
    for path, facts in files:
        fid = "file:" + path
        for use in facts["uses"]:
            owner = sym.keymap.get((path, use["owner"]), fid) if use["owner"] else fid
            if use["kind"] == "api":
                yield owner, "uses-api", "api:" + use["name"], "exact"
            elif use["kind"] == "ref":
                cands = sym.types_simple(use["name"], path)
                res = "exact" if len(cands) == 1 else "ambiguous"
                for dst in cands:
                    yield owner, "references", dst, res
            else:
                targets, res = _call_targets(sym, path, owner, use)
                for dst in targets:
                    kind = "instantiates" if dst.startswith("type:") else "calls"
                    yield owner, kind, dst, res
