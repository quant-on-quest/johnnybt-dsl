"""Exercise the schema-generating configuration metaprogramming base."""

import json
import unittest

from johnnybt_dsl import DSLError, run

WORDS = """
class FactorConfig < JohnnyBtDSL::Config
  field :reference, type: String, positional: true, required: true, doc: "Factor reference"
  field :weight, type: Numeric, default: 1, doc: "Scoring weight", impact: :strategy
  word :desc, doc: "Use descending ranks", returns: :self do
    self[:ascending] = false
    self
  end
  field :ascending, type: :boolean, default: true, doc: "Rank direction"
end

class AccountConfig < JohnnyBtDSL::Config
  field :capital, type: Numeric, min: 0, doc: "Initial capital"
end

class ExampleConfig < JohnnyBtDSL::Config
  describe "Example configuration"
  field :name, type: String, required: true, positional: true, doc: "Configuration name"
  field :offsets, type: Array, default: [0], doc: "Ordered offsets"
  one :account, of: AccountConfig, doc: "Account settings"
  many :factors, of: FactorConfig, item: :use, doc: "Ordered scoring factors"
end

class ExampleDSL < JohnnyBtDSL::Base
  sample "example.rb"
  entry :example, of: ExampleConfig, doc: "Declare an example"
end
"""


class ConfigTests(unittest.TestCase):
    """Keep runtime behavior, introspection and explicit declaration identity aligned."""

    def result(self, source: str, answer: str = "JohnnyBtDSL.ir") -> dict:
        return json.loads(run([(WORDS, "words.rb"), (source, "example.rb")], answer=answer))

    def test_nested_configuration_preserves_order_types_and_omission(self) -> None:
        result = self.result(
            """
example "sample" do
  account do
    capital 100
  end
  factors do
    use("first").desc.weight(0.7)
    use("second").weight(1)
  end
end
"""
        )
        data = result["declarations"]["example"][0]
        self.assertEqual(data["name"], "sample")
        self.assertNotIn("offsets", data)
        self.assertEqual(data["account"], {"capital": 100})
        self.assertEqual(data["factors"][0], {"reference": "first", "ascending": False, "weight": 0.7})
        self.assertIsInstance(data["factors"][0]["weight"], float)
        self.assertIsInstance(data["factors"][1]["weight"], int)
        self.assertNotIn("ascending", data["factors"][1])

    def test_schema_comes_from_the_actual_macros(self) -> None:
        result = self.result("", "JohnnyBtDSL.manifest")
        schema = result["dsls"][0]["schema"]
        self.assertEqual(schema["version"], 1)
        documents = {document["name"]: document for document in schema["documents"]}
        self.assertEqual(set(documents), {"ExampleConfig", "FactorConfig", "AccountConfig"})
        field = next(field for field in documents["FactorConfig"]["fields"] if field["name"] == "weight")
        self.assertEqual(field["description"], "Scoring weight")
        self.assertEqual(field["type"], "number")
        self.assertTrue(field["has_default"])
        self.assertEqual(field["default"], 1)
        self.assertEqual(field["impact"], "strategy")
        self.assertEqual(field["source"]["path"], "words.rb")
        self.assertGreater(field["source"]["line"], 0)
        self.assertEqual(schema["entries"][0]["block"], "ExampleConfig")

    def test_required_unknown_and_invalid_values_fail_at_the_statement(self) -> None:
        for source in [
            "example 42",
            'example "sample" do typo 1 end',
            'example "sample" do account { capital -1 } end',
        ]:
            with self.subTest(source=source):
                result = self.result(source)
                self.assertEqual(result["declarations"]["example"], [])
                failure = result["failures"][0]
                self.assertEqual(failure["file"], "example.rb")
                self.assertEqual(failure["line"], 1)

    def test_windows_internal_frames_are_skipped_without_rewriting_user_paths(self) -> None:
        source = r"""
ExampleDSL.trouble("invalid", [
  'C:\build\mrbgems\mruby-dsl\mrblib\config.rb:42',
  'mrblib\hash.rb:12',
  'C:\project\example.rb:7'
])
"""
        failure = self.result(source)["failures"][0]
        self.assertEqual(failure["file"], r"C:\project\example.rb")
        self.assertEqual(failure["line"], 7)
        self.assertEqual(failure["backtrace"][0], r"C:\build\mrbgems\mruby-dsl\mrblib\config.rb:42")

    def test_inheritance_isolated_defaults_and_explicit_null(self) -> None:
        source = """
class ChildConfig < ExampleConfig
  field :offsets, type: Array, default: [1], doc: "Child offsets", override: true
  field :note, type: String, nullable: true, doc: "Optional note"
end
first = ChildConfig.new(name: "first")
second = ChildConfig.new(name: "second")
first.offsets << 2
second.note nil
$answer = [first.offsets, second.offsets, ExampleConfig.new.offsets, second.to_h]
"""
        result = json.loads(run([WORDS, source], answer="$answer.to_json"))
        self.assertEqual(result, [[1, 2], [1], [0], {"name": "second", "note": None}])

    def test_custom_validation_is_reflected_as_runtime_only(self) -> None:
        source = """
class ValidatedConfig < JohnnyBtDSL::Config
  field :value, type: Integer, doc: "Even value"
  validates :even, fields: [:value], doc: "Require an even value" do
    raise ArgumentError, "must be even" unless value.nil? || value % 2 == 0
  end
end
"""
        result = json.loads(run([source], answer="ValidatedConfig.schema.to_json"))
        self.assertTrue(result["validations"][0]["runtime_only"])
        with self.assertRaises(DSLError):
            run([source, "ValidatedConfig.new(value: 3).validate!"], answer="nil.to_s")

    def test_parent_extensions_and_overrides_stay_aligned_with_inherited_methods(self) -> None:
        source = """
class ParentConfig < JohnnyBtDSL::Config
  field :first, type: Integer, doc: "First value"
end
class ChildConfig < ParentConfig
  field :own, type: String, doc: "Own value"
end
ParentConfig.field :late, type: Integer, doc: "Late parent field"
child = ChildConfig.new
child.late 3
$answer = [child.to_h, ChildConfig.schema["fields"].map { |field| field["name"] }]
"""
        self.assertEqual(
            json.loads(run([source], answer="$answer.to_json")),
            [{"late": 3}, ["first", "late", "own"]],
        )

    def test_word_defaults_are_generated_from_the_parameter_schema(self) -> None:
        source = """
class WordConfig < JohnnyBtDSL::Config
  open true
  word :set, doc: "Set values", returns: :self,
    arguments: [{name: :amount, type: Integer, default: 3, doc: "Amount"}],
    keywords: [{name: :note, type: String, default: "default", doc: "Note"}] do |amount, note:|
    self[:amount] = amount
    self[:note] = note
    self
  end
end
"""
        result = json.loads(run([source, "$result = WordConfig.new.set.to_h"], answer="$result.to_json"))
        self.assertEqual(result, {"amount": 3, "note": "default"})

    def test_fields_cannot_replace_runtime_helpers(self) -> None:
        for name in ("class", "to_h", "validate!", "explicit_values"):
            with self.subTest(name=name), self.assertRaises(DSLError):
                run([f'class ReservedConfig < JohnnyBtDSL::Config; field :"{name}", type: String, doc: "Bad"; end'])

    def test_word_bindings_support_prepended_collectors(self) -> None:
        source = """
module Params
  def method_missing(name, *args, **kwargs)
    super
  end
end
class PrependedConfig < JohnnyBtDSL::Config
  prepend Params
  def setting(value)
    value
  end
  word :setting, doc: "Existing setting", arguments: [{name: :value, type: Integer, doc: "Value"}]
end
"""
        self.assertEqual(run([source], answer="PrependedConfig.new.setting(42).to_s"), "42")


if __name__ == "__main__":
    unittest.main()
