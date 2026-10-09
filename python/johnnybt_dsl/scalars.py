"""Restore explicit exact scalar leaves from the language-neutral declaration IR."""

import math
import re

_DECIMAL = re.compile(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\Z")


def decode_float64(value: object) -> object:
    """Restore finite float64 decimal leaves without evaluating DSL arithmetic.

    Args:
        value: JSON-compatible declaration data returned by a language engine.

    Returns:
        The same structure with explicitly tagged decimal leaves decoded to float.

    Raises:
        ValueError: If a reserved leaf is malformed, nondecimal or nonfinite.
    """
    if isinstance(value, dict):
        if "$jbt.float64" in value:
            text = value["$jbt.float64"]
            if set(value) != {"$jbt.float64"} or not isinstance(text, str) or _DECIMAL.fullmatch(text) is None:
                raise ValueError("float64 declaration leaves require exactly one quoted decimal value")
            parsed = float(text)
            if not math.isfinite(parsed):
                raise ValueError("float64 declaration leaves must be finite")
            return parsed
        return {key: decode_float64(item) for key, item in value.items()}
    if isinstance(value, list):
        return [decode_float64(item) for item in value]
    return value
