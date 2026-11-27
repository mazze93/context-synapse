"""Write a generated tree to disk without ever destroying earlier output.

Side effects (the only module in cgcore that writes files):
  - refuses to write into a non-empty directory that has no manifest, so
    it can never clobber a folder it did not create;
  - writes a file only when its bytes change (idempotent: a rerun on the
    same input writes nothing and leaves mtimes alone);
  - before overwriting or dropping a file, moves the old copy to
    .archive/<previous-head>-<previous-manifest-digest>/ (Obsidian ignores
    dot-folders), so hand edits and past builds stay recoverable;
  - writes .codegraph-manifest.json last; it lists every file with its
    sha256 and has no timestamp.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
from typing import Any, Dict

MANIFEST = ".codegraph-manifest.json"
ARCHIVE = ".archive"


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _read(path: str) -> bytes:
    with open(path, "rb") as handle:
        return handle.read()


def _archive(out_dir: str, rel: str, slot: str) -> None:
    src = os.path.join(out_dir, rel)
    dst = os.path.join(out_dir, ARCHIVE, slot, rel)
    if os.path.exists(dst) and _read(dst) == _read(src):
        os.remove(src)
        return
    n = 1
    while os.path.exists(dst):
        dst = os.path.join(out_dir, ARCHIVE, slot + "." + str(n), rel)
        n += 1
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.move(src, dst)


def write_tree(out_dir: str, files: Dict[str, str], meta: Dict[str, Any]) -> Dict[str, int]:
    """Sync `files` ({relative path: text}) into out_dir. Returns counts."""
    manifest_path = os.path.join(out_dir, MANIFEST)
    previous: Dict[str, Any] = {"files": {}, "head": "none"}
    if os.path.isdir(out_dir) and os.listdir(out_dir):
        if not os.path.exists(manifest_path):
            raise RuntimeError(out_dir + " is not empty and has no " + MANIFEST
                               + "; refusing to write into a folder codegraph did not create")
        previous = json.loads(_read(manifest_path).decode("utf-8"))
    slot = str(previous.get("head", "none"))[:12] + "-" + _sha(
        json.dumps(previous, sort_keys=True).encode())[:8]
    counts = {"written": 0, "unchanged": 0, "archived": 0}
    encoded = {rel: text.encode("utf-8") for rel, text in files.items()}
    for rel in sorted(encoded):
        if rel.startswith((ARCHIVE + "/", MANIFEST)) or ".." in rel.split("/"):
            raise ValueError("refusing generated path " + rel)
        path = os.path.join(out_dir, rel)
        if os.path.exists(path):
            if _read(path) == encoded[rel]:
                counts["unchanged"] += 1
                continue
            _archive(out_dir, rel, slot)
            counts["archived"] += 1
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as handle:
            handle.write(encoded[rel])
        counts["written"] += 1
    for rel in sorted(previous["files"]):
        if rel not in encoded and os.path.exists(os.path.join(out_dir, rel)):
            _archive(out_dir, rel, slot)
            counts["archived"] += 1
    manifest = dict(meta)
    manifest["files"] = {rel: _sha(encoded[rel]) for rel in sorted(encoded)}
    text = json.dumps(manifest, sort_keys=True, indent=1, ensure_ascii=False) + "\n"
    if not os.path.exists(manifest_path) or _read(manifest_path) != text.encode("utf-8"):
        os.makedirs(out_dir, exist_ok=True)
        with open(manifest_path, "wb") as handle:
            handle.write(text.encode("utf-8"))
    return counts
