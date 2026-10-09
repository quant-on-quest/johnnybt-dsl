"""Check the installed wheel's complete numeric path against Python binary64."""

import json
import math
import random
import struct
import unittest

from johnnybt_dsl import DSLError, compile, run


def bits(value: float) -> bytes:
    """Return a platform-independent binary64 bit pattern."""
    return struct.pack(">d", value)


class FloatTransportTests(unittest.TestCase):
    """Exercise actual source, bytecode, string conversion and JSON transport."""

    def test_decimal_paths_retain_every_bit(self) -> None:
        texts = [
            "0.0",
            "-0.0",
            "0.7",
            "0.3",
            "0.010000000000000002",
            "0.00010000000000000002",
            "1.0000000000000003e-5",
            "5e-324",
            "2.2250738585072014e-308",
            "1.7976931348623157e308",
            "9007199254740992.0",
            "1.0000000000000002",
        ]
        for text in texts:
            with self.subTest(text=text):
                source = f'$value = [{text}, "{text}".to_f, Float("{text}"), JSON.parse("{text}")]'
                for chunk in (source, compile(source, "float.rb")):
                    actual = json.loads(run([(chunk, "float.rb")], answer="$value.to_json"))
                    self.assertEqual([bits(value) for value in actual], [bits(float(text))] * 4)
                    self.assertTrue(all(isinstance(value, float) for value in actual))

    def test_sampled_finite_bit_patterns_round_trip(self) -> None:
        samples = random.Random(20261008)
        values = [struct.unpack(">d", samples.getrandbits(64).to_bytes(8, "big"))[0] for _ in range(512)]
        values = [value for value in values if math.isfinite(value)]
        source = "$values = [" + ",".join(repr(value) for value in values) + "]"
        for chunk in (source, compile(source, "samples.rb")):
            actual = json.loads(run([(chunk, "samples.rb")], answer="$values.to_json"))
            self.assertEqual([bits(value) for value in actual], [bits(value) for value in values])

    def test_nonfinite_json_is_refused(self) -> None:
        for expression in ("1.0 / 0.0", "-1.0 / 0.0", "0.0 / 0.0"):
            with self.subTest(expression=expression), self.assertRaises(DSLError):
                run([], answer=f"({expression}).to_json")

    def test_decimal_prefix_and_underscore_behavior_is_preserved(self) -> None:
        actual = json.loads(
            run([], answer='["0x10".to_f, "  -0.7tail".to_f, "1e+".to_f, 1_000.25, "1_000.25".to_f].to_json')
        )
        self.assertEqual(
            [bits(value) for value in actual], [bits(value) for value in [0.0, -0.7, 1.0, 1000.25, 1000.25]]
        )


if __name__ == "__main__":
    unittest.main()
