"""Load and validate a codegraph config file.

Everything repo-specific lives in the config; the core never hard-codes a
path, module name or language. Unknown keys are rejected so a typo fails
loudly instead of being silently ignored.
"""
from __future__ import annotations

import json
from typing import Any, Dict

DEFAULTS: Dict[str, Any] = {
    "schema": "codegraph-config/1",
    "project": "",
    "language": "swift",
    "manifest": "",
    "exclude_prefixes": [],
    "module_fallback": [],
    "api_probes": [],
    "test_modules": [],
    "output_dir": "codegraph-vault",
}


def load(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as handle:
        raw = json.load(handle)
    unknown = sorted(set(raw) - set(DEFAULTS))
    if unknown:
        raise ValueError("unknown config keys: " + ", ".join(unknown))
    if raw.get("schema", DEFAULTS["schema"]) != DEFAULTS["schema"]:
        raise ValueError("unsupported config schema: " + str(raw.get("schema")))
    cfg = dict(DEFAULTS)
    cfg.update(raw)
    return cfg


def fingerprint(cfg: Dict[str, Any]) -> str:
    """Canonical text of the config, recorded in every output manifest."""
    return json.dumps(cfg, sort_keys=True, separators=(",", ":"))
