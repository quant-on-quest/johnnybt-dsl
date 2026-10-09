"""Export metadata by loading word libraries, never consumer declarations."""

from __future__ import annotations

import json
import sys


def main() -> int:
    """Run one isolated metadata export requested by the schema adapter."""
    try:
        from johnnybt_dsl import run

        decoded: object = json.loads(sys.stdin.read())
        if not isinstance(decoded, list):
            raise ValueError("Schema input must be an array of filename/source pairs")
        chunks: list[tuple[str, str]] = []
        for chunk in decoded:
            if (
                not isinstance(chunk, list)
                or len(chunk) != 2
                or not isinstance(chunk[0], str)
                or not isinstance(chunk[1], str)
            ):
                raise ValueError("Schema input must contain filename/source string pairs")
            chunks.append((chunk[0], chunk[1]))
        if run([], answer="JohnnyBtDSL.const_defined?(:Config).to_s") != "true":
            raise ValueError("The installed DSL engine has no Config schema API; use the new engine wheel")
        output = run([(source, path) for path, source in chunks], answer="JohnnyBtDSL.manifest")
        sys.stdout.write(output)
        return 0
    except Exception as error:  # noqa: BLE001 - isolate word-definition failures from the editor protocol process
        sys.stderr.write(str(error) + "\n")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
