"""CycloneDX 1.5 JSON SBOM from the graph's dependency nodes.

Pure and deterministic: no timestamp, no random serialNumber, sorted
components. This is the hand-off format for Theatre of Dependencies
(`theatre scan <sbom> --json --offline`), which reads CycloneDX by purl.
With no external dependencies the SBOM is empty but valid.
"""
from __future__ import annotations

from typing import Any, Dict, List
from urllib.parse import urlparse

from . import model


def _purl(attrs: Dict[str, Any]) -> str:
    """pkg:swift/<host>/<path>@<version> per the purl Swift type."""
    loc = attrs.get("location", "")
    parsed = urlparse(loc)
    if parsed.scheme in ("http", "https") and parsed.netloc:
        path = parsed.path.strip("/")
        if path.endswith(".git"):
            path = path[:-4]
        purl = "pkg:swift/" + parsed.netloc.lower() + "/" + path
    else:
        purl = "pkg:swift/" + attrs["name"]
    version = attrs.get("version") or attrs.get("revision") or ""
    return purl + ("@" + version if version else "")


def build(graph: model.Graph, project: str) -> Dict[str, Any]:
    nodes = graph["nodes"]
    pkg = next((n for n in sorted(nodes) if nodes[n]["kind"] == "package"), "")
    root_ref = "root:" + (nodes[pkg]["name"] if pkg else project)
    components: List[Dict[str, Any]] = []
    direct: List[str] = []
    for nid in sorted(nodes):
        attrs = nodes[nid]
        if attrs["kind"] != "dependency":
            continue
        purl = _purl(attrs)
        comp: Dict[str, Any] = {"type": "library", "bom-ref": purl, "name": attrs["name"],
                                "purl": purl}
        if attrs.get("version"):
            comp["version"] = attrs["version"]
        if attrs.get("location"):
            comp["externalReferences"] = [{"type": "vcs", "url": attrs["location"]}]
        components.append(comp)
        if attrs.get("direct"):
            direct.append(purl)
    return {
        "bomFormat": "CycloneDX", "specVersion": "1.5", "version": 1,
        "metadata": {
            "tools": {"components": [{"type": "application", "name": "codegraph"}]},
            "component": {"type": "application", "bom-ref": root_ref,
                          "name": nodes[pkg]["name"] if pkg else project},
        },
        "components": components,
        # Only the root's edges are known offline. Listing a component with
        # an empty dependsOn would assert it has none, so they are omitted.
        "dependencies": [{"ref": root_ref, "dependsOn": sorted(direct)}],
    }
