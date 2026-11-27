"""Unit and end-to-end tests for codegraph. Standard library only.

Run from the repo root:
    python3 -m unittest discover -s tools/codegraph/tests -v
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

from cgcore import model, resolve, writer  # noqa: E402
from cgcore.adapters import swiftpm  # noqa: E402
from cgcore.adapters.swift_facts import extract  # noqa: E402
from cgcore.adapters.swift_lexer import tokenize  # noqa: E402

SCRIPT = os.path.join(os.path.dirname(HERE), "codegraph.py")


class LexerTests(unittest.TestCase):
    def test_comments_are_dropped_including_nested_blocks(self):
        toks = tokenize("a /* x /* y */ z */ b // c\nd")
        self.assertEqual([t[1] for t in toks], ["a", "b", "d"])

    def test_interpolation_code_is_tokenised(self):
        toks = tokenize('let s = "x\\(compute(a: 1))y"')
        texts = [t[1] for t in toks]
        self.assertIn("compute", texts)
        self.assertIn("str_open", [t[0] for t in toks])

    def test_raw_and_multiline_strings_hide_their_content(self):
        toks = tokenize('let a = #"func fake() { }"#\nlet b = """\nfunc no()\n"""\nc')
        self.assertNotIn("fake", [t[1] for t in toks])
        self.assertNotIn("no", [t[1] for t in toks])
        self.assertEqual(toks[-1][1:], ("c", 5))

    def test_numbers_keep_exponents_and_ranges_split(self):
        self.assertEqual([t[1] for t in tokenize("1e-5 0..<3")], ["1e-5", "0", ".", ".", "<", "3"])


class FactsTests(unittest.TestCase):
    SRC = """
import Foundation
public struct Prior: Codable, Sendable {
    public var alpha: Double
    public init(alpha: Double, beta: Double = 1) { self.alpha = alpha }
    public static func uniform() -> Prior { Prior(alpha: 1) }
    class func notAType() {}
}
protocol Store { func load(id: String) -> Int }
extension Prior { mutating func widen(by amount: Double) { helper(amount) } }
func helper(_ x: Double) { let h = "k".hashValue; _ = try! Data() }
"""

    def setUp(self):
        self.facts = extract(self.SRC, ("hashValue", "try!"))
        self.keys = [d["key"] for d in self.facts["decls"]]

    def test_declarations_and_selectors(self):
        for key in ("type:Prior", "func:Prior.init(alpha:beta:)", "func:Prior.uniform()",
                    "func:Prior.notAType()", "type:Store", "func:Store.load(id:)",
                    "func:Prior.widen(by:)", "func:helper(_:)"):
            self.assertIn(key, self.keys)

    def test_class_func_is_a_modifier_not_a_type(self):
        self.assertNotIn("type:func", self.keys)

    def test_protocol_requirement_has_no_body(self):
        decl = next(d for d in self.facts["decls"] if d["key"] == "func:Store.load(id:)")
        self.assertTrue(decl["requirement"])

    def test_inheritance_defaults_and_probes(self):
        prior = next(d for d in self.facts["decls"] if d["key"] == "type:Prior")
        self.assertEqual(prior["inherits"], ["Codable", "Sendable"])
        init = next(d for d in self.facts["decls"] if d["key"] == "func:Prior.init(alpha:beta:)")
        self.assertEqual([p["default"] for p in init["params"]], [False, True])
        probes = sorted(u["name"] for u in self.facts["uses"] if u["kind"] == "api")
        self.assertEqual(probes, ["hashValue", "try!"])

    def test_call_owner_is_enclosing_function(self):
        call = next(u for u in self.facts["uses"] if u["kind"] == "call" and u["name"] == "helper")
        self.assertEqual(call["owner"], "func:Prior.widen(by:)")


class ResolveTests(unittest.TestCase):
    def test_default_and_trailing_closure_compatibility(self):
        params = [{"label": "a", "default": False, "closure": False},
                  {"label": "b", "default": True, "closure": False},
                  {"label": "done", "default": False, "closure": True}]
        self.assertTrue(resolve.compatible(params, ["a", "done"], False))
        self.assertTrue(resolve.compatible(params, ["a"], True))
        self.assertFalse(resolve.compatible(params, ["a"], False))
        self.assertFalse(resolve.compatible(params, ["b", "a"], False))


class ModelTests(unittest.TestCase):
    def test_delta_apply_roundtrip_and_moved_classification(self):
        old = {"nodes": {"a": {"kind": "x", "loc": {"line": 1}}, "b": {"kind": "y"}},
               "edges": {model.edge_key("a", "calls", "b"): {"count": 1, "resolution": "exact"},
                         model.edge_key("a", "uses", "a"): {"count": 1, "resolution": "exact"}}}
        new = {"nodes": {"a": {"kind": "x", "loc": {"line": 9}}, "c": {"kind": "z"}},
               "edges": {model.edge_key("a", "calls", "c"): {"count": 2, "resolution": "exact"},
                         model.edge_key("a", "uses", "a"): {"count": 5, "resolution": "unique"}}}
        change = model.delta(old, new)
        self.assertEqual(model.canonical(model.apply(old, change)), model.canonical(new))
        self.assertEqual(change["nodes_moved"], ["a"])
        self.assertEqual(model.semantic_touched(change), ["b", "c"])


class ManifestTests(unittest.TestCase):
    def test_package_dependencies_and_lockfile(self):
        man = swiftpm.parse_manifest(
            'let p = Package(name: "P", dependencies: [.package(url: "https://github.com/a/b.git",'
            ' from: "1.2.0")], targets: [.target(name: "T", dependencies: [.product(name: "B",'
            ' package: "b")])])')
        self.assertEqual(man["packages"][0]["identity"], "b")
        self.assertEqual(man["targets"][0]["deps"][0]["package"], "b")
        pins = swiftpm.parse_resolved('{"pins":[{"identity":"b","location":"x",'
                                      '"state":{"version":"1.2.3","revision":"abc"}}],"version":2}')
        self.assertEqual(pins[0]["version"], "1.2.3")


def _git(repo, *args):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid",
               GIT_AUTHOR_DATE="2026-01-01T00:00:00Z", GIT_COMMITTER_DATE="2026-01-01T00:00:00Z")
    subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True, env=env)


class EndToEndTests(unittest.TestCase):
    """Build a three-commit repo with a merge, fold it, check the law, and
    check that rerunning is a no-op while a new HEAD archives old output."""

    def _commit(self, repo, rel, text, msg):
        path = os.path.join(repo, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)
        _git(repo, "add", "-A")
        _git(repo, "commit", "-q", "-m", msg)

    def _run(self, repo, out):
        cfg = os.path.join(repo, "cfg.json")
        with open(cfg, "w", encoding="utf-8") as handle:
            handle.write('{"project": "demo", "manifest": "swiftpm", '
                         '"module_fallback": [{"prefix": "Sources/", "segment": 1}]}')
        proc = subprocess.run([sys.executable, SCRIPT, "--repo", repo, "--config", cfg, "--out", out],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        return proc.stdout

    def test_fold_law_idempotence_and_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = os.path.join(tmp, "repo")
            os.makedirs(repo)
            _git(repo, "init", "-q", "-b", "main")
            self._commit(repo, "Sources/A/a.swift", "struct A { func f() {} }\n", "one")
            _git(repo, "checkout", "-q", "-b", "side")
            self._commit(repo, "Sources/A/b.swift", "struct B { func g() { A().f() } }\n", "side")
            _git(repo, "checkout", "-q", "main")
            self._commit(repo, "Sources/A/a.swift", "struct A { func f() {}\n func h() {} }\n", "two")
            _git(repo, "merge", "-q", "--no-ff", "side", "-m", "merge")
            out = os.path.join(tmp, "vault")
            first = self._run(repo, out)
            self.assertIn("per-commit 4/4", first)
            self.assertIn("mainline fold == head: True", first)
            self.assertIn("written 0 ", self._run(repo, out))
            note = os.path.join(out, "Functions", "Func - A.B.g().md")
            with open(note, encoding="utf-8") as handle:
                self.assertIn("[[Func - A.A.f()|A.f()]]", handle.read())
            self._commit(repo, "Sources/A/a.swift", "struct A { func f() {} }\n", "drop h")
            third = self._run(repo, out)
            self.assertNotIn("archived 0", third)
            self.assertTrue(os.path.isdir(os.path.join(out, writer.ARCHIVE)))
            self.assertTrue(os.path.exists(os.path.join(out, "Removed", "Func - A.A.h().md")))

    def test_refuses_foreign_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "notes.md"), "w", encoding="utf-8") as handle:
                handle.write("mine")
            with self.assertRaises(RuntimeError):
                writer.write_tree(tmp, {"x.md": "y"}, {})


if __name__ == "__main__":
    unittest.main()
