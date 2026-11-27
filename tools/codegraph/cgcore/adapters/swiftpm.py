"""SwiftPM adapter: read Package.swift and Package.resolved statically.

Pure functions; nothing is executed, nothing is fetched. The manifest is
lexed with the Swift lexer and the well-known PackageDescription calls are
read off the token stream. A manifest that builds its targets with loops or
variables will be under-read; that shows up as missing targets, not as a
crash.

Contract (language-neutral manifest facts, consumed by cgcore/build.py):
  {package, targets: [{name, kind, path, deps: [{kind, name, package}]}],
   products: [{name, kind, targets}],
   packages: [{identity, location, requirement}],
   pins: [{identity, location, version, revision, branch}]}
"""
from __future__ import annotations

import json
from typing import Dict, List, Optional, Tuple

from .swift_lexer import Token, tokenize

TARGET_CALLS = {
    "target": "library", "executableTarget": "executable", "testTarget": "test",
    "macro": "macro", "plugin": "plugin", "systemLibrary": "system",
    "binaryTarget": "binary",
}
PRODUCT_CALLS = {"library": "library", "executable": "executable", "plugin": "plugin"}


def _match(tokens: List[Token], i: int, open_ch: str, close_ch: str) -> int:
    depth = 0
    for j in range(i, len(tokens)):
        if tokens[j][1] == open_ch and tokens[j][0] == "punct":
            depth += 1
        elif tokens[j][1] == close_ch and tokens[j][0] == "punct":
            depth -= 1
            if depth == 0:
                return j
    return len(tokens) - 1


def _args(tokens: List[Token], open_i: int) -> Tuple[Dict[str, Tuple[int, int]], int]:
    """Labelled argument ranges of the call whose '(' is at open_i."""
    close_i = _match(tokens, open_i, "(", ")")
    out: Dict[str, Tuple[int, int]] = {}
    depth, start, pos = 0, open_i + 1, 0
    for j in range(open_i + 1, close_i + 1):
        text = tokens[j][1]
        if text in "([{" and tokens[j][0] == "punct":
            depth += 1
        elif text in ")]}" and tokens[j][0] == "punct" and j != close_i:
            depth -= 1
        if (text == "," and depth == 0) or j == close_i:
            if j > start:
                if tokens[start][0] == "id" and start + 1 < j and tokens[start + 1][1] == ":":
                    out[tokens[start][1]] = (start + 2, j)
                else:
                    out["_" + str(pos)] = (start, j)
            pos += 1
            start = j + 1
    return out, close_i


def _first_str(tokens: List[Token], rng: Optional[Tuple[int, int]]) -> str:
    if rng is None:
        return ""
    for kind, text, _ in tokens[rng[0]:rng[1]]:
        if kind == "str":
            return text
    return ""


def _strs(tokens: List[Token], rng: Optional[Tuple[int, int]]) -> List[str]:
    if rng is None:
        return []
    return [text for kind, text, _ in tokens[rng[0]:rng[1]] if kind == "str"]


def _deps(tokens: List[Token], rng: Optional[Tuple[int, int]]) -> List[dict]:
    if rng is None:
        return []
    out, j = [], rng[0]
    while j < rng[1]:
        kind, text, _ = tokens[j]
        if kind == "str" and tokens[j - 1][1] in ("[", ","):
            out.append({"kind": "byName", "name": text, "package": ""})
        elif kind == "id" and tokens[j - 1][1] == "." and j + 1 < rng[1] \
                and tokens[j + 1][1] == "(" and text in ("product", "target", "byName"):
            args, close_i = _args(tokens, j + 1)
            out.append({"kind": text, "name": _first_str(tokens, args.get("name")),
                        "package": _first_str(tokens, args.get("package"))})
            j = close_i
        j += 1
    return out


def _requirement(tokens: List[Token], args: Dict[str, Tuple[int, int]]) -> str:
    for key in ("exact", "from", "branch", "revision", "path"):
        if key in args:
            return key + " " + _first_str(tokens, args[key])
    for key, rng in sorted(args.items()):
        if key.startswith("_"):
            texts = " ".join(t[1] if t[0] != "str" else '"' + t[1] + '"'
                             for t in tokens[rng[0]:rng[1]])
            return texts
    return ""


def parse_manifest(src: str) -> dict:
    """Read Package.swift source into manifest facts."""
    t = tokenize(src)
    facts = {"package": "", "targets": [], "products": [], "packages": []}
    for i, (kind, text, _) in enumerate(t):
        if kind != "id" or i + 1 >= len(t) or t[i + 1][1] != "(":
            continue
        args, _ = _args(t, i + 1)
        prev = t[i - 1][1] if i else ""
        if text == "Package" and prev != "." and not facts["package"]:
            facts["package"] = _first_str(t, args.get("name"))
        elif prev == "." and text in TARGET_CALLS and "name" in args:
            name = _first_str(t, args.get("name"))
            tkind = TARGET_CALLS[text]
            default_root = "Tests/" if tkind == "test" else "Sources/"
            facts["targets"].append({
                "name": name, "kind": tkind,
                "path": _first_str(t, args.get("path")) or default_root + name,
                "deps": _deps(t, args.get("dependencies")),
            })
        elif prev == "." and text in PRODUCT_CALLS and "targets" in args:
            facts["products"].append({"name": _first_str(t, args.get("name")),
                                      "kind": PRODUCT_CALLS[text],
                                      "targets": _strs(t, args.get("targets"))})
        elif prev == "." and text == "package" and ("url" in args or "path" in args or "id" in args):
            location = _first_str(t, args.get("url") or args.get("path") or args.get("id"))
            identity = location.rstrip("/").split("/")[-1].lower()
            if identity.endswith(".git"):
                identity = identity[:-4]
            facts["packages"].append({"identity": identity, "location": location,
                                      "requirement": _requirement(t, args)})
    for key in ("targets", "products", "packages"):
        facts[key].sort(key=lambda d: json.dumps(d, sort_keys=True))
    return facts


def parse_resolved(src: str) -> List[dict]:
    """Read Package.resolved (format v1, v2 or v3) into pins."""
    try:
        data = json.loads(src)
    except ValueError:
        return []
    raw = data.get("pins") or data.get("object", {}).get("pins") or []
    pins = []
    for pin in raw:
        state = pin.get("state", {})
        location = pin.get("location") or pin.get("repositoryURL") or ""
        pins.append({
            "identity": (pin.get("identity") or pin.get("package") or "").lower(),
            "location": location,
            "version": state.get("version") or "",
            "revision": state.get("revision") or "",
            "branch": state.get("branch") or "",
        })
    pins.sort(key=lambda d: (d["identity"], d["location"]))
    return pins
