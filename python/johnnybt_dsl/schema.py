"""Export language-owned schema independently of any application framework."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Sequence


def builtin_sources() -> tuple[Path, ...]:
    """Return installed source resources for built-in language utilities."""
    return tuple(sorted(Path(__file__).with_name("words").glob("*.rb")))


def export_schema(sources: Sequence[tuple[str, str]], *, timeout: float = 10) -> dict[str, object]:
    """Load trusted word definitions in a bounded metadata-only process.

    Args:
        sources: Filename/source pairs for language definitions, not consumer files.
        timeout: Maximum metadata-worker duration in seconds.

    Returns:
        The language manifest with installed source locations for built-in helpers.

    Raises:
        ValueError: If definitions fail or the manifest is not an object.
        subprocess.TimeoutExpired: If a definition exceeds the duration bound.
    """
    environment = os.environ.copy()
    environment["PYTHONPATH"] = os.pathsep.join(str(path) for path in sys.path if path)
    result = subprocess.run(
        [sys.executable, "-m", "johnnybt_dsl.schema_worker"],
        input=json.dumps(tuple(sources)),
        capture_output=True,
        text=True,
        timeout=timeout,
        env=environment,
        check=False,
    )
    if result.returncode:
        raise ValueError(result.stderr.strip() or f"DSL schema export failed (exit {result.returncode})")
    decoded: object = json.loads(result.stdout)
    if not isinstance(decoded, dict):
        raise ValueError("The DSL schema manifest must be an object")
    manifest = cast("dict[str, object]", decoded)
    utilities = manifest.get("utilities")
    if isinstance(utilities, list):
        resources = {source.name: source.resolve() for source in builtin_sources()}
        named_resources = {source.stem: source.resolve() for source in builtin_sources()}
        for utility in utilities:
            if not isinstance(utility, dict) or not isinstance(utility.get("source"), dict):
                continue
            source = utility["source"]
            path = source.get("path")
            if not isinstance(path, str):
                continue
            normalized = path.replace("\\", "/")
            resource = None
            if not normalized:
                resource = named_resources.get(str(utility.get("name", "")))
            elif "/python/johnnybt_dsl/words/" in normalized or normalized.startswith("words/"):
                resource = resources.get(Path(normalized).name)
            if resource is not None:
                source["path"] = str(resource)
    return manifest
