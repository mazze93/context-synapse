"""Obsidian note names, folders, links and safe text. Pure.

Obsidian forbids * " \\ / < > : | ? # ^ [ ] in note names, and link text
cannot hold | or ]. Every name is derived from the node id alone, so the
same node always gets the same note, in every run and at every commit.
"""
from __future__ import annotations

import json
import re
from typing import Any, Dict, List

FOLDERS = {
    "package": "Package", "product": "Products", "module": "Modules",
    "dependency": "Dependencies", "framework": "Frameworks", "file": "Files",
    "type": "Types", "func": "Functions", "extern": "External", "api": "API",
}
PREFIX = {
    "package": "Package", "product": "Product", "module": "Module",
    "dependency": "Dependency", "framework": "Framework", "file": "File",
    "type": "Type", "func": "Func", "extern": "Extern", "api": "API",
}
_FORBIDDEN = re.compile(r'[*"\\/<>:|?#^\[\]]')


def _clean(text: str) -> str:
    return _FORBIDDEN.sub("_", text)


def selector_display(selector: str) -> str:
    """lighthouseFloor(for:isLighthouse:) -> lighthouseFloor(for,isLighthouse)"""
    if "(" not in selector:
        return selector
    name, rest = selector.split("(", 1)
    labels = [p for p in rest.rstrip(")").split(":") if p]
    return name + "(" + ",".join(labels) + ")"


def note_name(nid: str, attrs: Dict[str, Any]) -> str:
    kind = attrs["kind"]
    body = nid.split(":", 1)[1]
    if kind == "file":
        body = " › ".join(attrs["path"].split("/"))
    elif kind == "func":
        head = body[: len(body) - len(attrs["selector"])]
        body = head + selector_display(attrs["selector"])
    return PREFIX[kind] + " - " + _clean(body)


def commit_name(sha: str) -> str:
    return "Commit " + sha[:12]


def folder(attrs: Dict[str, Any], removed: bool) -> str:
    return "Removed" if removed else FOLDERS[attrs["kind"]]


def short_label(nid: str, attrs: Dict[str, Any]) -> str:
    kind = attrs["kind"]
    if kind == "func":
        owner = attrs["container"].split(".")[-1] + "." if attrs["container"] else ""
        return owner + attrs["selector"]
    if kind == "type":
        return attrs["qual"]
    if kind == "file":
        return attrs["path"]
    return attrs.get("name", nid)


def link(name: str, label: str = "") -> str:
    label = label.replace("|", "¦").replace("]", ")").replace("[", "(")
    return "[[" + name + ("|" + label if label and label != name else "") + "]]"


def text(value: str) -> str:
    """Neutralise wiki/markup syntax in text copied from git (subjects)."""
    value = value.replace("[[", "[ [").replace("]]", "] ]").replace("|", "¦")
    return value.lstrip("#>").strip() or "(empty)"


def frontmatter(fields: Dict[str, Any], tags: List[str]) -> str:
    """YAML frontmatter; values are JSON-encoded, which YAML 1.2 parses."""
    lines = ["---"]
    for key in sorted(fields):
        lines.append(key + ": " + json.dumps(fields[key], ensure_ascii=False, sort_keys=True))
    lines.append("tags: " + json.dumps(sorted(set(tags)), ensure_ascii=False))
    lines.append("---")
    return "\n".join(lines) + "\n"


def tag(text_value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_/-]", "-", text_value)
