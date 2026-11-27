"""Adapter registry.

A language adapter turns one source file into neutral facts; a manifest
adapter turns a package manifest (and lockfile) into neutral dependency
facts. To add a language, add a module here and register it; nothing in
cgcore outside this package knows any language.
"""
from __future__ import annotations

from typing import Callable, Dict, List, Tuple

from . import swift_facts, swiftpm

# Bump when an adapter's output for the same input could change; it keys
# the parse cache and is recorded in every output manifest.
ADAPTER_VERSION = "swift-1.0.0"

# name -> (file suffixes, extract(src, api_probes), ambient method names)
LANGUAGES: Dict[str, Tuple[Tuple[str, ...], Callable[..., dict], Tuple[str, ...]]] = {
    "swift": ((".swift",), swift_facts.extract, swift_facts.AMBIENT_METHODS),
}

# name -> (manifest file names, lockfile names, parse_manifest, parse_lock)
MANIFESTS: Dict[str, Tuple[List[str], List[str], Callable[[str], dict], Callable[[str], list]]] = {
    "swiftpm": (["Package.swift"], ["Package.resolved"], swiftpm.parse_manifest, swiftpm.parse_resolved),
}
