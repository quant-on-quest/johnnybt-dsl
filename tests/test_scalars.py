"""Check exact scalar helpers as built-in language and transport capabilities."""

import json
import unittest

from johnnybt_dsl import run


class ScalarTests(unittest.TestCase):
    """Require no host-specific Ruby injection to create or decode exact leaves."""

    def test_float64_is_present_in_a_bare_vm(self) -> None:
        result = json.loads(run([], answer='float64("0.010000000000000002").to_json'))
        self.assertEqual(result, {"$jbt.float64": "0.010000000000000002"})

    def test_loads_decodes_nested_exact_scalars(self) -> None:
        from johnnybt_dsl import loads

        result = loads('{"weight": {"$jbt.float64": "0.010000000000000002"}}')
        self.assertEqual(result["weight"].hex(), float("0.010000000000000002").hex())

    def test_malformed_and_nonfinite_leaves_are_rejected(self) -> None:
        from johnnybt_dsl import decode_float64

        for text in ("nan", "inf", "1e309", "", "1_000", "0x1", " 0.3"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                decode_float64({"$jbt.float64": text})
        with self.assertRaises(ValueError):
            decode_float64({"$jbt.float64": "0.3", "other": 1})

    def test_signed_zero_and_subnormal_retain_bits(self) -> None:
        from johnnybt_dsl import decode_float64

        for value in (-0.0, 5e-324):
            self.assertEqual(decode_float64({"$jbt.float64": repr(value)}).hex(), value.hex())

    def test_builtin_schema_source_is_available_in_the_installed_package(self) -> None:
        from pathlib import Path

        from johnnybt_dsl import export_schema

        manifest = export_schema(())
        scalar = next(item for item in manifest["utilities"] if item["name"] == "float64")
        source = Path(scalar["source"]["path"])
        self.assertTrue(source.is_file())
        self.assertIn("def float64", source.read_text())


if __name__ == "__main__":
    unittest.main()
