"""Project one snapshot (one commit's tree) into a graph.

Pure: inputs are already-parsed facts; output is a Graph. Language-neutral:
it reads only the adapter contract (see cgcore/adapters/swift_facts.py and
swiftpm.py docstrings).

Node id prefixes:
  pkg:     the package            product: a built product
  module:  a target / module      dep:     an external package dependency
  fw:      an imported module that is not a target (system framework)
  file:    a source file          type:    a type (module-qualified)
  func:    a function / init      extern:  a conformance target not in the repo
  api:     an API probe from the config (e.g. hashValue)
"""
from __future__ import annotations

import hashlib
from typing import Any, Dict, List, Optional, Tuple

from . import model, resolve


def module_of(path: str, manifest: Optional[dict], fallback: List[dict]) -> str:
    if manifest:
        best = ""
        best_len = -1
        for target in manifest["targets"]:
            root = target["path"].rstrip("/") + "/"
            if path.startswith(root) and len(root) > best_len:
                best, best_len = target["name"], len(root)
        if best:
            return best
    for rule in fallback:
        if path.startswith(rule["prefix"]):
            if "name" in rule:
                return rule["name"]
            parts = path.split("/")
            if len(parts) > rule["segment"] + 1:
                return parts[rule["segment"]]
    return "(root)"


def _add_edge(g: model.Graph, src: str, kind: str, dst: str, resolution: str = "exact") -> None:
    if src == dst:
        return
    key = model.edge_key(src, kind, dst)
    rank = resolve.RESOLUTION_RANK
    cur = g["edges"].get(key)
    if cur is None:
        g["edges"][key] = {"count": 1, "resolution": resolution}
    else:
        cur["count"] += 1
        if rank[resolution] < rank[cur["resolution"]]:
            cur["resolution"] = resolution


def _manifest_nodes(g: model.Graph, manifest: Optional[dict], pins: List[dict]) -> None:
    if not manifest:
        return
    pkg = "pkg:" + (manifest["package"] or "(package)")
    g["nodes"][pkg] = {"kind": "package", "name": manifest["package"]}
    target_names = {t["name"] for t in manifest["targets"]}
    pin_by_id = {p["identity"]: p for p in pins}
    for dep in manifest["packages"]:
        pin = pin_by_id.get(dep["identity"], {})
        g["nodes"]["dep:" + dep["identity"]] = {
            "kind": "dependency", "name": dep["identity"], "location": dep["location"],
            "requirement": dep["requirement"], "version": pin.get("version", ""),
            "revision": pin.get("revision", ""), "branch": pin.get("branch", ""), "direct": True}
        _add_edge(g, pkg, "requires", "dep:" + dep["identity"])
    for pin in pins:  # transitive pins: present in the lockfile, not the manifest
        nid = "dep:" + pin["identity"]
        if nid not in g["nodes"]:
            g["nodes"][nid] = {"kind": "dependency", "name": pin["identity"],
                               "location": pin["location"], "requirement": "",
                               "version": pin["version"], "revision": pin["revision"],
                               "branch": pin["branch"], "direct": False}
            _add_edge(g, pkg, "pins", nid)
    for target in manifest["targets"]:
        mid = "module:" + target["name"]
        g["nodes"][mid] = {"kind": "module", "subkind": target["kind"],
                           "name": target["name"], "path": target["path"]}
        _add_edge(g, pkg, "contains", mid)
        for dep in target["deps"]:
            if dep["kind"] == "product" and dep["package"]:
                _add_edge(g, mid, "depends-on", "dep:" + dep["package"].lower())
            elif dep["name"] in target_names:
                _add_edge(g, mid, "depends-on", "module:" + dep["name"])
            else:
                _add_edge(g, mid, "depends-on", "dep:" + dep["name"].lower())
    for product in manifest["products"]:
        pid = "product:" + product["name"]
        g["nodes"][pid] = {"kind": "product", "subkind": product["kind"], "name": product["name"]}
        _add_edge(g, pkg, "contains", pid)
        for name in product["targets"]:
            _add_edge(g, pid, "built-from", "module:" + name)


def _file_nodes(g: model.Graph, files: List[Tuple[str, dict]], modules: Dict[str, str],
                target_names: set) -> None:
    for path, facts in files:
        mod = modules[path]
        fid = "file:" + path
        g["nodes"][fid] = {"kind": "file", "name": path.split("/")[-1], "path": path,
                           "module": mod}
        mid = "module:" + mod
        if mid not in g["nodes"]:
            g["nodes"][mid] = {"kind": "module", "subkind": "inferred", "name": mod, "path": ""}
        _add_edge(g, mid, "contains", fid)
        for imp in facts["imports"]:
            target = "module:" + imp["module"] if imp["module"] in target_names \
                else "fw:" + imp["module"]
            if target not in g["nodes"]:
                g["nodes"][target] = {"kind": "framework", "name": imp["module"]}
            _add_edge(g, fid, "imports", target)


def project(files: List[Tuple[str, dict]], manifest: Optional[dict], pins: List[dict],
            cfg: Dict[str, Any], ambient: Tuple[str, ...] = ()) -> model.Graph:
    """Build the graph for one snapshot. `files` must be sorted by path."""
    g = model.empty()
    _manifest_nodes(g, manifest, pins)
    modules = {path: module_of(path, manifest, cfg["module_fallback"]) for path, _ in files}
    target_names = {t["name"] for t in manifest["targets"]} if manifest else set()
    target_names |= set(modules.values())
    _file_nodes(g, files, modules, target_names)
    symbols = resolve.Symbols(files, modules, ambient)
    for nid, attrs in symbols.nodes.items():
        g["nodes"][nid] = attrs
    for src, kind, dst in symbols.structure_edges:
        _add_edge(g, src, kind, dst)
    for src, kind, dst, resolution in resolve.use_edges(files, modules, symbols):
        if kind == "uses-api" and dst not in g["nodes"]:
            g["nodes"][dst] = {"kind": "api", "name": dst[len("api:"):]}
        if kind == "conforms" and dst.startswith("extern:") and dst not in g["nodes"]:
            g["nodes"][dst] = {"kind": "extern", "name": dst[len("extern:"):]}
        _add_edge(g, src, kind, dst, resolution)
    return g


def blob_cache_key(adapter_version: str, cfg_fingerprint: str, blob: str) -> str:
    return hashlib.sha256((adapter_version + "\0" + cfg_fingerprint + "\0" + blob).encode()).hexdigest()
