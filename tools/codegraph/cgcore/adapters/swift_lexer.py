"""Swift lexer for codegraph.

Pure function: source text in, token list out. No I/O, no global state.

Tokens are (kind, text, line) tuples:
  id     identifier or keyword (backticks stripped)
  num    numeric literal
  str    string literal; text is the literal's raw content for simple
         literals, or "" when the literal holds interpolation (the
         interpolated code is emitted as ordinary tokens between a
         `str_open` and `str_close` pair so calls inside it still count)
  attr   attribute, e.g. "@escaping"
  pound  compiler directive / literal, e.g. "#if", "#available"
  op     operator run ("->", "==", "+=", ...); "<", ">", "?", "!" and "."
         are always single-character tokens so generics and optional
         chaining stay parseable
  punct  one of { } ( ) [ ] , : ; \\
Comments (line, block, nested block) are dropped.
"""
from __future__ import annotations

from typing import List, Tuple

Token = Tuple[str, str, int]

_PUNCT = set("{}()[],:;\\")
_SINGLE_OPS = set("<>?!.")
_OP_CHARS = set("+-*/%=&|^~")


def _is_ident_start(ch: str) -> bool:
    return ch == "_" or ch.isalpha()


def _is_ident_char(ch: str) -> bool:
    return ch == "_" or ch.isalnum()


class _Lexer:
    """Single-use lexer; call run() once."""

    def __init__(self, src: str) -> None:
        self.src = src
        self.n = len(src)
        self.i = 0
        self.line = 1
        self.out: List[Token] = []

    # ── helpers ────────────────────────────────────────────────────────────
    def _peek(self, k: int = 0) -> str:
        j = self.i + k
        return self.src[j] if j < self.n else ""

    def _emit(self, kind: str, text: str, line: int) -> None:
        self.out.append((kind, text, line))

    def _advance(self, count: int = 1) -> None:
        for _ in range(count):
            if self.i < self.n and self.src[self.i] == "\n":
                self.line += 1
            self.i += 1

    # ── entry ──────────────────────────────────────────────────────────────
    def run(self) -> List[Token]:
        self._code(stop_at_paren=False)
        return self.out

    def _code(self, stop_at_paren: bool) -> None:
        """Lex code. If stop_at_paren, return after the ')' closing an
        interpolation (depth counted from the '\\(' that opened it)."""
        depth = 0
        while self.i < self.n:
            ch = self._peek()
            nxt = self._peek(1)
            if ch in " \t\r\n":
                self._advance()
            elif ch == "/" and nxt == "/":
                while self.i < self.n and self._peek() != "\n":
                    self._advance()
            elif ch == "/" and nxt == "*":
                self._block_comment()
            elif ch == '"' or (ch == "#" and self._raw_string_ahead()):
                self._string()
            elif _is_ident_start(ch):
                self._ident()
            elif ch == "`":
                self._backtick_ident()
            elif ch.isdigit():
                self._number()
            elif ch == "@" and _is_ident_start(nxt):
                line = self.line
                self._advance()
                start = self.i
                while self.i < self.n and _is_ident_char(self._peek()):
                    self._advance()
                self._emit("attr", "@" + self.src[start:self.i], line)
            elif ch == "#" and _is_ident_start(nxt):
                line = self.line
                self._advance()
                start = self.i
                while self.i < self.n and _is_ident_char(self._peek()):
                    self._advance()
                self._emit("pound", "#" + self.src[start:self.i], line)
            elif ch == "$" and (nxt.isdigit() or _is_ident_start(nxt)):
                line = self.line
                start = self.i
                self._advance()
                while self.i < self.n and _is_ident_char(self._peek()):
                    self._advance()
                self._emit("id", self.src[start:self.i], line)
            elif ch in _PUNCT:
                if stop_at_paren and ch == "(":
                    depth += 1
                if stop_at_paren and ch == ")":
                    if depth == 0:
                        self._advance()
                        return
                    depth -= 1
                self._emit("punct", ch, self.line)
                self._advance()
            elif ch == "-" and nxt == ">":
                self._emit("op", "->", self.line)
                self._advance(2)
            elif ch in _SINGLE_OPS:
                self._emit("op", ch, self.line)
                self._advance()
            elif ch in _OP_CHARS:
                line = self.line
                start = self.i
                while self.i < self.n and self._peek() in _OP_CHARS:
                    if self._peek() == "/" and self._peek(1) in "/*":
                        break
                    self._advance()
                self._emit("op", self.src[start:self.i], line)
            else:
                # Unknown character (e.g. stray unicode): skip it, never crash.
                self._advance()

    # ── comments ───────────────────────────────────────────────────────────
    def _block_comment(self) -> None:
        depth = 0
        while self.i < self.n:
            if self._peek() == "/" and self._peek(1) == "*":
                depth += 1
                self._advance(2)
            elif self._peek() == "*" and self._peek(1) == "/":
                depth -= 1
                self._advance(2)
                if depth == 0:
                    return
            else:
                self._advance()

    # ── identifiers and numbers ────────────────────────────────────────────
    def _ident(self) -> None:
        line = self.line
        start = self.i
        while self.i < self.n and _is_ident_char(self._peek()):
            self._advance()
        self._emit("id", self.src[start:self.i], line)

    def _backtick_ident(self) -> None:
        line = self.line
        self._advance()
        start = self.i
        while self.i < self.n and self._peek() not in "`\n":
            self._advance()
        text = self.src[start:self.i]
        self._advance()
        self._emit("id", text, line)

    def _number(self) -> None:
        line = self.line
        start = self.i
        while self.i < self.n:
            ch = self._peek()
            if _is_ident_char(ch):
                self._advance()
            elif ch == "." and self._peek(1).isdigit():
                self._advance()
            elif ch in "+-" and self._peek(1).isdigit() and self._exponent_sign(start):
                self._advance()
            else:
                break
        self._emit("num", self.src[start:self.i], line)

    def _exponent_sign(self, start: int) -> bool:
        """True when the +/- at self.i is an exponent sign (1e-5, 0x1p+3)."""
        prev = self.src[self.i - 1]
        is_hex = self.src[start:self.i].lower().startswith("0x")
        return (prev in "pP") if is_hex else (prev in "eE")

    # ── strings ────────────────────────────────────────────────────────────
    def _raw_string_ahead(self) -> bool:
        j = self.i
        while j < self.n and self.src[j] == "#":
            j += 1
        return j < self.n and self.src[j] == '"' and j > self.i

    def _string(self) -> None:
        line = self.line
        hashes = 0
        while self._peek() == "#":
            hashes += 1
            self._advance()
        multiline = self.src.startswith('"""', self.i)
        self._advance(3 if multiline else 1)
        closer = ('"""' if multiline else '"') + "#" * hashes
        escape = "\\" + "#" * hashes
        parts: List[str] = []
        interpolated = False
        open_index = len(self.out)
        while self.i < self.n:
            if self.src.startswith(closer, self.i):
                self._advance(len(closer))
                break
            if self.src.startswith(escape + "(", self.i):
                if not interpolated:
                    self.out.insert(open_index, ("str_open", "", line))
                    interpolated = True
                self._advance(len(escape) + 1)
                self._code(stop_at_paren=True)
                continue
            if self.src.startswith(escape, self.i):
                parts.append(self.src[self.i:self.i + len(escape) + 1])
                self._advance(len(escape) + 1)
                continue
            if not multiline and self._peek() == "\n":
                break  # unterminated single-line literal: stop at EOL
            parts.append(self._peek())
            self._advance()
        if interpolated:
            self._emit("str_close", "", self.line)
        else:
            self._emit("str", "".join(parts), line)


def tokenize(src: str) -> List[Token]:
    """Return the token list for Swift source text."""
    return _Lexer(src).run()
