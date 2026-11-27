"""Fold over the git log: project every commit, diff against its first
parent, and track each node's history.

Reads git objects only (never the working tree), so the result is a pure
function of (repository objects, rev, config, adapter version).

Memory: keeps one graph per commit so merge commits can diff against any
earlier parent. Fine for hundreds of commits; for very long histories,
evict graphs once all children are processed.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional, Tuple

from . import build, gitio, model
from .adapters import ADAPTER_VERSION, LANGUAGES, MANIFESTS


class _Parser:
    """Parses blobs through the configured adapters, cached by blob sha."""

    def __init__(self, reader: gitio.BlobReader, cfg: Dict[str, Any]) -> None:
        self.reader = reader
        self.cfg = cfg
        self.suffixes, self.extract, self.ambient = LANGUAGES[cfg["language"]]
        self.probes = tuple(cfg["api_probes"])
        self.cache: Dict[str, Any] = {}

    def _text(self, blob: str) -> str:
        return self.reader.read(blob).decode("utf-8", "replace")

    def source(self, blob: str) -> dict:
        key = "src:" + blob
        if key not in self.cache:
            self.cache[key] = self.extract(self._text(blob), self.probes)
        return self.cache[key]

    def manifest(self, blob: Optional[str], lock_blob: Optional[str]) -> Tuple[Optional[dict], List[dict]]:
        if not self.cfg["manifest"] or blob is None:
            return None, []
        _, _, parse_manifest, parse_lock = MANIFESTS[self.cfg["manifest"]]
        key = "man:" + blob
        if key not in self.cache:
            self.cache[key] = parse_manifest(self._text(blob))
        pins: List[dict] = []
        if lock_blob:
            lkey = "lock:" + lock_blob
            if lkey not in self.cache:
                self.cache[lkey] = parse_lock(self._text(lock_blob))
            pins = self.cache[lkey]
        return self.cache[key], pins


def _snapshot(repo: str, sha: str, parser: _Parser) -> Tuple[model.Graph, Dict[str, str]]:
    cfg = parser.cfg
    names, locks = ([], [])
    if cfg["manifest"]:
        names, locks, _, _ = MANIFESTS[cfg["manifest"]]
    excluded = tuple(cfg["exclude_prefixes"])
    files: List[Tuple[str, dict]] = []
    manifest_blob: Optional[str] = None
    lock_blob: Optional[str] = None
    blobs: Dict[str, str] = {}
    for path, blob in gitio.tree(repo, sha):
        if path in names:
            manifest_blob = blob
            blobs[path] = blob
        elif path in locks:
            lock_blob = blob
            blobs[path] = blob
        elif path.endswith(parser.suffixes) and not path.startswith(excluded):
            files.append((path, parser.source(blob)))
            blobs[path] = blob
    manifest, pins = parser.manifest(manifest_blob, lock_blob)
    return build.project(files, manifest, pins, cfg, parser.ambient), blobs


def run(repo: str, rev: str, cfg: Dict[str, Any]) -> Dict[str, Any]:
    """Fold the history reachable from rev. Returns everything the writers
    need: commits, per-commit deltas, node history, the head graph, and the
    fold-law verification result."""
    head = gitio.resolve(repo, rev)
    commits = gitio.commits(repo, head)
    graphs: Dict[str, model.Graph] = {}
    deltas: Dict[str, Dict[str, Any]] = {}
    history: Dict[str, Dict[str, Any]] = {}
    with gitio.BlobReader(repo) as reader:
        parser = _Parser(reader, cfg)
        for c in commits:
            sha = str(c["sha"])
            graph, _ = _snapshot(repo, sha, parser)
            parents = list(c["parents"])  # type: ignore[arg-type]
            base = graphs[parents[0]] if parents else model.empty()
            change = model.delta(base, graph)
            graphs[sha] = graph
            deltas[sha] = change
            _track(history, sha, change)
    verified = _verify_fold(commits, graphs, deltas, head)
    return {"head": head, "commits": commits, "deltas": deltas, "history": history,
            "graph": graphs[head], "fold_law": verified, "adapter": ADAPTER_VERSION}


def _track(history: Dict[str, Dict[str, Any]], sha: str, change: Dict[str, Any]) -> None:
    for nid in change["nodes_added"]:
        entry = history.setdefault(nid, {"first_commit": sha, "last_commit": sha,
                                         "changes": 0, "removed_in": ""})
        entry["removed_in"] = ""
    for nid in model.semantic_touched(change):
        entry = history.setdefault(nid, {"first_commit": sha, "last_commit": sha,
                                         "changes": 0, "removed_in": ""})
        entry["last_commit"] = sha
        entry["changes"] += 1
    for nid in change["nodes_removed"]:
        history[nid]["removed_in"] = sha
    for source in ("nodes_added", "nodes_changed"):
        for nid, attrs in change[source].items():
            history[nid]["attrs"] = attrs


def _verify_fold(commits: List[Dict[str, Any]], graphs: Dict[str, model.Graph],
                 deltas: Dict[str, Dict[str, Any]], head: str) -> Dict[str, Any]:
    """Check apply(parent, delta) == projection for every commit, and that
    folding deltas along HEAD's first-parent chain from empty reproduces
    the HEAD projection."""
    per_commit_ok = 0
    failures: List[str] = []
    for c in commits:
        sha = str(c["sha"])
        parents = list(c["parents"])
        base = graphs[parents[0]] if parents else model.empty()
        if model.canonical(model.apply(base, deltas[sha])) == model.canonical(graphs[sha]):
            per_commit_ok += 1
        else:
            failures.append(sha)
    parent_of = {str(c["sha"]): (list(c["parents"]) or [None])[0] for c in commits}
    chain: List[str] = []
    cur: Optional[str] = head
    while cur:
        chain.append(cur)
        cur = parent_of[cur]
    state = model.empty()
    for sha in reversed(chain):
        state = model.apply(state, deltas[sha])
    chain_ok = model.canonical(state) == model.canonical(graphs[head])
    return {"commits_checked": len(commits), "commits_ok": per_commit_ok,
            "failures": failures, "mainline_length": len(chain),
            "mainline_fold_equals_head": chain_ok,
            "head_digest": model.digest(graphs[head])}
