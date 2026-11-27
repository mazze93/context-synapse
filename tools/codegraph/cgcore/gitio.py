"""Read-only git plumbing. Reads objects; never touches the working tree.

Side effects: spawns `git` subprocesses against the given repository. All
output is parsed from NUL- or unit-separator-delimited plumbing formats so
user config (quotepath, color, pager, locale) cannot change the result.
"""
from __future__ import annotations

import os
import subprocess
from typing import Dict, List, Optional, Tuple

_ENV_PIN = {
    "LC_ALL": "C", "LANG": "C", "GIT_PAGER": "cat", "GIT_OPTIONAL_LOCKS": "0",
    "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0",
}


def _env() -> Dict[str, str]:
    env = dict(os.environ)
    env.update(_ENV_PIN)
    env.pop("GIT_DIR", None)
    env.pop("GIT_WORK_TREE", None)
    return env


def git(repo: str, *args: str) -> bytes:
    return subprocess.run(["git", "-C", repo, "-c", "core.quotepath=off", *args],
                          check=True, capture_output=True, env=_env()).stdout


def resolve(repo: str, rev: str) -> str:
    return git(repo, "rev-parse", "--verify", rev + "^{commit}").decode().strip()


def commits(repo: str, rev: str) -> List[Dict[str, object]]:
    """All commits reachable from rev, parents before children (topo order).

    Each: {sha, parents, date (committer, ISO 8601), subject, generation}.
    generation = 1 + max(parent generations); it never changes when new
    commits are added, unlike a position in the list.
    """
    fmt = "%H%x1f%P%x1f%cI%x1f%s%x1e"
    raw = git(repo, "log", "--topo-order", "--reverse", "--format=" + fmt, rev).decode("utf-8", "replace")
    out: List[Dict[str, object]] = []
    gen: Dict[str, int] = {}
    for record in raw.split("\x1e"):
        record = record.strip("\n")
        if not record:
            continue
        sha, parents, date, subject = record.split("\x1f", 3)
        plist = parents.split() if parents else []
        gen[sha] = 1 + max((gen.get(p, 0) for p in plist), default=0)
        out.append({"sha": sha, "parents": plist, "date": date, "subject": subject,
                    "generation": gen[sha]})
    return out


def tree(repo: str, sha: str) -> List[Tuple[str, str]]:
    """(path, blob sha) for every blob in the commit's tree, sorted by path."""
    raw = git(repo, "ls-tree", "-r", "--full-tree", "-z", sha)
    out = []
    for entry in raw.split(b"\0"):
        if not entry:
            continue
        meta, path = entry.split(b"\t", 1)
        mode, kind, obj = meta.split(b" ")
        if kind == b"blob" and mode != b"160000":
            out.append((path.decode("utf-8", "surrogateescape"), obj.decode()))
    out.sort()
    return out


class BlobReader:
    """Persistent `git cat-file --batch` reader. Use as a context manager."""

    def __init__(self, repo: str) -> None:
        self.proc: Optional[subprocess.Popen] = subprocess.Popen(
            ["git", "-C", repo, "cat-file", "--batch"], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, env=_env())

    def read(self, sha: str) -> bytes:
        assert self.proc and self.proc.stdin and self.proc.stdout
        self.proc.stdin.write(sha.encode() + b"\n")
        self.proc.stdin.flush()
        header = self.proc.stdout.readline().split()
        if len(header) < 3 or header[1] == b"missing":
            raise KeyError("missing object " + sha)
        size = int(header[2])
        data = self.proc.stdout.read(size)
        self.proc.stdout.read(1)  # trailing newline
        return data

    def close(self) -> None:
        if self.proc:
            assert self.proc.stdin
            self.proc.stdin.close()
            self.proc.wait()
            self.proc = None

    def __enter__(self) -> "BlobReader":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()
