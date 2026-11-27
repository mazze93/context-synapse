"""Swift adapter: turn one Swift source file into language-neutral facts.

Pure function `extract(src) -> dict`. The dict shape is the adapter
contract every language adapter must produce (see cgcore/build.py):

  imports: [{module, line, testable}]
  decls:   [{key, kind, subkind, name, container, selector, params,
             extension, inherits, access, static, requirement,
             line, end_line, digest}]
  uses:    [{kind: call|ref|api, owner, name, labels, receiver,
             trailing, line}]

`key` is "type:<Qual>" or "func:<Container>.<selector>" (container "" for
top-level). `owner` on a use is the key of the innermost enclosing decl,
or "" for file-level code. Name resolution across files happens later,
in the language-neutral build step.

Known limits (by design, recorded rather than hidden):
  - No type inference: a call through a variable (`x.foo()`) is resolved
    by selector only and may come back ambiguous.
  - Local functions and closures are folded into their enclosing decl.
  - Property declarations are not nodes; their bodies count toward the
    enclosing type.
"""
from __future__ import annotations

import hashlib
from typing import Dict, List, Optional, Tuple

from .swift_lexer import Token, tokenize

TYPE_KEYWORDS = {"struct", "enum", "class", "actor", "protocol", "extension"}
FUNC_KEYWORDS = {"func", "init", "deinit", "subscript"}
MODIFIERS = {
    "public", "private", "fileprivate", "internal", "open", "static", "class",
    "final", "override", "mutating", "nonmutating", "nonisolated", "convenience",
    "required", "lazy", "weak", "unowned", "dynamic", "indirect", "optional",
    "isolated", "distributed", "consuming", "borrowing",
}
DECL_STARTERS = MODIFIERS | FUNC_KEYWORDS | TYPE_KEYWORDS | {
    "var", "let", "case", "typealias", "associatedtype", "import",
}
ACCESS = {"public", "private", "fileprivate", "internal", "open"}
NOT_CALLS = {
    "if", "guard", "while", "for", "switch", "return", "catch", "in", "where",
    "try", "await", "throw", "repeat", "case", "else", "as", "is", "let", "var",
    "func", "init", "self", "Self", "super", "some", "any", "defer", "do",
}
# Swift standard-library / Foundation method names. A call through a
# variable receiver to one of these is never classed `unique`, because the
# variable is far more likely an Array, Set, Dictionary or FileHandle than
# a repo type that happens to declare the same selector.
AMBIENT_METHODS = (
    "append", "insert", "remove", "removeAll", "removeValue", "contains", "write",
    "map", "filter", "reduce", "first", "last", "sorted", "sort", "joined", "update",
    "index", "firstIndex", "forEach", "compactMap", "flatMap", "min", "max", "count",
    "encode", "decode", "read", "close", "load", "save", "set", "get", "add", "merge",
)

# A probe ending in "()" matches only a call site; a bare name matches any
# use; "try!" / "as!" match the forced forms.
API_PROBES_DEFAULT = (
    "hashValue", "Date()", "UUID()", "random()", "print()", "fatalError()",
    "precondition()", "try!", "as!", "ProcessInfo", "FileManager", "URLSession",
)


def _match(tokens: List[Token], i: int, open_ch: str, close_ch: str) -> int:
    """Index of the token closing the bracket opened at tokens[i]."""
    depth = 0
    for j in range(i, len(tokens)):
        text = tokens[j][1]
        if tokens[j][0] in ("punct", "op") and text == open_ch:
            depth += 1
        elif tokens[j][0] in ("punct", "op") and text == close_ch:
            depth -= 1
            if depth == 0:
                return j
    return len(tokens) - 1


def _skip_generics(tokens: List[Token], i: int) -> int:
    if i < len(tokens) and tokens[i][1] == "<":
        return _match(tokens, i, "<", ">") + 1
    return i


def _split_top(tokens: List[Token], lo: int, hi: int) -> List[Tuple[int, int]]:
    """Split tokens[lo:hi] on commas at bracket depth 0."""
    parts, depth, start = [], 0, lo
    for j in range(lo, hi):
        text = tokens[j][1]
        if text in "([{" and tokens[j][0] == "punct":
            depth += 1
        elif text in ")]}" and tokens[j][0] == "punct":
            depth -= 1
        elif text == "," and depth == 0:
            parts.append((start, j))
            start = j + 1
    if start < hi:
        parts.append((start, hi))
    return parts


def _params(tokens: List[Token], open_i: int) -> Tuple[List[dict], int]:
    """Parse a declaration parameter list starting at '('."""
    close_i = _match(tokens, open_i, "(", ")")
    params = []
    for lo, hi in _split_top(tokens, open_i + 1, close_i):
        seg = [t for t in tokens[lo:hi] if t[0] != "attr"]
        colon = next((k for k, t in enumerate(seg) if t[1] == ":"), None)
        if colon is None or colon == 0:
            continue
        names = [t[1] for t in seg[:colon] if t[0] == "id"]
        rest = seg[colon + 1:]
        params.append({
            "label": names[0] if names else "_",
            "default": any(t[1] == "=" for t in rest),
            "closure": any(t[1] == "->" for t in rest),
        })
    return params, close_i


def _call_labels(tokens: List[Token], open_i: int) -> Tuple[List[str], int]:
    close_i = _match(tokens, open_i, "(", ")")
    labels = []
    for lo, hi in _split_top(tokens, open_i + 1, close_i):
        if hi - lo >= 2 and tokens[lo][0] == "id" and tokens[lo + 1][1] == ":":
            labels.append(tokens[lo][1])
        else:
            labels.append("_")
    return labels, close_i


def _selector(name: str, labels: List[str]) -> str:
    return name + "(" + "".join(lbl + ":" for lbl in labels) + ")"


def _digest(tokens: List[Token], lo: int, hi: int) -> str:
    text = "\x1f".join(t[1] for t in tokens[lo:hi + 1])
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def _modifiers(tokens: List[Token], i: int) -> Tuple[str, bool, int]:
    """Walk back from a decl keyword over modifiers and attributes."""
    access, static, j = "", False, i - 1
    while j >= 0:
        kind, text, _ = tokens[j]
        if kind == "attr":
            j -= 1
        elif kind == "punct" and text == ")" and j > 0:
            k = j  # attribute or modifier argument, e.g. private(set)
            depth = 0
            while k >= 0:
                if tokens[k][1] == ")":
                    depth += 1
                elif tokens[k][1] == "(":
                    depth -= 1
                    if depth == 0:
                        break
                k -= 1
            j = k - 1
        elif kind == "id" and text in MODIFIERS:
            access = text if text in ACCESS and not access else access
            static = static or text in ("static", "class")
            j -= 1
        else:
            break
    return access or "internal", static, j + 1


class _Extractor:
    def __init__(self, src: str, api_probes: Tuple[str, ...]) -> None:
        self.t = tokenize(src)
        self.api_bare = {p for p in api_probes if not p.endswith(("()", "!"))}
        self.api_call = {p[:-2] for p in api_probes if p.endswith("()")}
        self.api_forced = {p[:-1] for p in api_probes if p.endswith("!")}
        self.imports: List[dict] = []
        self.decls: List[dict] = []
        self.uses: List[dict] = []
        self.stack: List[Tuple[str, Optional[dict]]] = []
        self.pending: Dict[int, dict] = {}

    # ── scope helpers ─────────────────────────────────────────────────────
    def _owner(self) -> str:
        for kind, decl in reversed(self.stack):
            if decl is not None:
                return decl["key"]
        return ""

    def _type_container(self) -> Tuple[str, bool]:
        """Qualified name of the innermost type scope, and whether a function
        scope sits between us and it (i.e. we are inside a function)."""
        for kind, decl in reversed(self.stack):
            if decl is None:
                continue
            if decl["kind"] == "func":
                return "", True
            return decl["name_qual"], False
        return "", False

    # ── declarations ──────────────────────────────────────────────────────
    def _type_decl(self, i: int) -> int:
        kw = self.t[i][1]
        prev = self.t[i - 1][1] if i else ""
        nxt = self.t[i + 1] if i + 1 < len(self.t) else ("", "", 0)
        if prev in (".", ":", ",") or nxt[0] != "id" or \
                (kw == "class" and nxt[1] in DECL_STARTERS):
            return i + 1
        access, static, start = _modifiers(self.t, i)
        j = i + 1
        name_parts = [self.t[j][1]]
        j += 1
        while kw == "extension" and j + 1 < len(self.t) and self.t[j][1] == "." \
                and self.t[j + 1][0] == "id":
            name_parts.append(self.t[j + 1][1])
            j += 2
        j = _skip_generics(self.t, j)
        inherits: List[str] = []
        if j < len(self.t) and self.t[j][1] == ":":
            j += 1
            while j < len(self.t) and self.t[j][1] not in ("{", "where"):
                if self.t[j][0] == "id" and self.t[j - 1][1] in (":", ","):
                    inherits.append(self.t[j][1])
                j = _skip_generics(self.t, j + 1)
        while j < len(self.t) and self.t[j][1] != "{":
            j += 1
        container, in_func = self._type_container()
        name = ".".join(name_parts)
        qual = name if kw == "extension" or not container else container + "." + name
        decl = {
            "key": "type:" + qual, "kind": "type",
            "subkind": "extension" if kw == "extension" else kw,
            "name": name_parts[-1], "name_qual": qual, "container": container,
            "selector": "", "params": [], "extension": kw == "extension",
            "inherits": inherits, "access": access, "static": False,
            "requirement": False, "local": in_func,
            "line": self.t[i][2], "end_line": self.t[i][2], "_start": start,
        }
        self.decls.append(decl)
        self.pending[j] = decl
        return j

    def _func_decl(self, i: int) -> int:
        kw = self.t[i][1]
        prev = self.t[i - 1][1] if i else ""
        if prev == "." or (kw == "init" and prev in ("self", "super")):
            return i + 1
        access, static, start = _modifiers(self.t, i)
        j = i + 1
        name = kw
        if kw == "func" and j < len(self.t):
            name = self.t[j][1]
            j += 1
        while j < len(self.t) and self.t[j][1] in ("?", "!"):
            j += 1
        j = _skip_generics(self.t, j)
        params: List[dict] = []
        if j < len(self.t) and self.t[j][1] == "(":
            params, j = _params(self.t, j)
            j += 1
        while j < len(self.t):
            kind, text, _ = self.t[j]
            if text in ("{", "}") and kind == "punct":
                break
            if kind in ("id", "attr") and text in DECL_STARTERS and text not in ("throws",):
                break
            if kind == "attr" and self.t[j - 1][1] not in ("->", ":", ","):
                break
            j += 1
        container, in_func = self._type_container()
        if in_func:
            return j  # local function: folded into the enclosing decl
        has_body = j < len(self.t) and self.t[j][1] == "{"
        selector = name + "()" if kw == "deinit" else _selector(name, [p["label"] for p in params])
        decl = {
            "key": "func:" + (container + "." if container else "") + selector,
            "kind": "func", "subkind": kw if kw != "func" else "func",
            "name": name, "name_qual": "", "container": container,
            "selector": selector, "params": params, "extension": False,
            "inherits": [], "access": access, "static": static,
            "requirement": not has_body, "local": False,
            "line": self.t[i][2], "end_line": self.t[max(j - 1, i)][2], "_start": start,
        }
        decl["digest"] = _digest(self.t, start, max(j - 1, i))
        self.decls.append(decl)
        if has_body:
            self.pending[j] = decl
        return j

    # ── uses ──────────────────────────────────────────────────────────────
    def _use_at(self, i: int) -> None:
        kind, text, line = self.t[i]
        prev = self.t[i - 1][1] if i else ""
        nxt = self.t[i + 1][1] if i + 1 < len(self.t) else ""
        owner = self._owner()
        probe = None
        if text in self.api_bare:
            probe = text
        elif text in self.api_call and nxt == "(":
            probe = text + "()"
        if probe:
            self.uses.append({"kind": "api", "owner": owner, "name": probe, "labels": [],
                              "receiver": None, "trailing": False, "line": line})
        if text in self.api_forced and nxt == "!":
            self.uses.append({"kind": "api", "owner": owner, "name": text + "!", "labels": [],
                              "receiver": None, "trailing": False, "line": line})
        if nxt == "(" and text not in NOT_CALLS and prev != "func":
            labels, close_i = _call_labels(self.t, i + 1)
            receiver = None
            if prev == "." and i >= 2 and self.t[i - 2][0] == "id" \
                    and self.t[i - 2][1] not in NOT_CALLS - {"self", "Self", "super"}:
                receiver = self.t[i - 2][1]
            trailing = close_i + 1 < len(self.t) and self.t[close_i + 1][1] == "{"
            self.uses.append({"kind": "call", "owner": owner, "name": text, "labels": labels,
                              "receiver": receiver, "trailing": trailing, "line": line})
        elif text == "init" and prev == "." and nxt == "(" and i >= 2:
            labels, _ = _call_labels(self.t, i + 1)
            self.uses.append({"kind": "call", "owner": owner, "name": "init", "labels": labels,
                              "receiver": self.t[i - 2][1], "trailing": False, "line": line})
        if text[:1].isupper():
            self.uses.append({"kind": "ref", "owner": owner, "name": text, "labels": [],
                              "receiver": None, "trailing": False, "line": line})

    # ── main loop ─────────────────────────────────────────────────────────
    def run(self) -> dict:
        i = 0
        while i < len(self.t):
            kind, text, line = self.t[i]
            if kind == "id" and text == "import" and i + 1 < len(self.t):
                testable = i > 0 and self.t[i - 1][1] == "@testable"
                j = i + 1
                if self.t[j][1] in ("struct", "class", "enum", "func", "protocol", "typealias"):
                    j += 1
                self.imports.append({"module": self.t[j][1], "line": line, "testable": testable})
                i = j + 1
                continue
            if kind == "id" and text in TYPE_KEYWORDS:
                i = self._type_decl(i)
                continue
            if kind == "id" and text in FUNC_KEYWORDS:
                new_i = self._func_decl(i)
                if new_i != i + 1:
                    i = new_i
                    continue
            if kind == "punct" and text == "{":
                decl = self.pending.pop(i, None)
                self.stack.append(("decl" if decl else "block", decl))
            elif kind == "punct" and text == "}":
                if self.stack:
                    _, decl = self.stack.pop()
                    if decl is not None:
                        decl["end_line"] = line
                        decl["digest"] = _digest(self.t, decl["_start"], i)
            elif kind == "id":
                self._use_at(i)
            i += 1
        for decl in self.decls:
            decl.pop("_start", None)
            decl.pop("name_qual", None)
            decl.setdefault("digest", "")
        return {"imports": self.imports, "decls": self.decls, "uses": self.uses}


def extract(src: str, api_probes: Tuple[str, ...] = API_PROBES_DEFAULT) -> dict:
    """Return language-neutral facts for one Swift source file."""
    return _Extractor(src, api_probes).run()
