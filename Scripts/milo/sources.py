from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path


def repository_root(argv: list[str]) -> Path:
    if "--" not in argv:
        raise RuntimeError("Pass the repository root after --")
    root = Path(argv[argv.index("--") + 1]).resolve()
    if not (root / "ItaLearn.xcodeproj").exists():
        raise RuntimeError(f"Not an ItaLearn checkout: {root}")
    return root


def verified_sources(root: Path) -> dict[str, Path]:
    manifest_path = root / "Art/Milo/sources.json"
    manifest = json.loads(manifest_path.read_text())
    variable = manifest["assetRootEnv"]
    asset_root = os.environ.get(variable)
    if not asset_root:
        raise RuntimeError(f"Set {variable} to the external Milo asset directory")
    resolved: dict[str, Path] = {}
    for name, record in manifest["sources"].items():
        path = Path(record["path"].replace("${MILO_ASSET_ROOT}", asset_root)).resolve()
        if not path.is_file():
            raise RuntimeError(f"Missing source {name}: {path}")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != record["sha256"]:
            raise RuntimeError(f"Checksum mismatch for {name}: {path}")
        resolved[name] = path
    return resolved


def safe_output(root: Path, relative: str) -> Path:
    output = (root / relative).resolve()
    art = (root / "Art/Milo").resolve()
    resources = (root / "ItaLearn/Resources").resolve()
    assets = (root / "ItaLearn/Assets.xcassets").resolve()
    if not any(output.is_relative_to(parent) for parent in (art, resources, assets)):
        raise RuntimeError(f"Refusing to write outside Milo outputs: {output}")
    if output.name == "Milo_Master.blend" and output.exists():
        raise RuntimeError("Milo_Master.blend is artist-owned and may not be overwritten")
    output.parent.mkdir(parents=True, exist_ok=True)
    return output
