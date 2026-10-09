# Transport exact scalar leaves without mruby decimal parsing or JSON rounding.
# This is declaration data, not an arithmetic value inside the Ruby program.
def float64(text)
  unless text.is_a?(String)
    raise ArgumentError, "float64 requires a quoted decimal string"
  end
  { "$jbt.float64" => text }
end

# The declaration owns its contract; hosts export it through the same manifest.
if JohnnyBtDSL.const_defined?(:Config)
  JohnnyBtDSL.utility :float64,
    doc: "Transport a quoted finite decimal as an exact scalar IR leaf, not a Ruby Float.",
    arguments: [{name: :text, type: String, doc: "Original decimal text"}],
    returns: :hash,
    invariants: [
      "Keep the decimal text, including signed zero and subnormal values.",
      "Do not use this tagged leaf in Ruby arithmetic.",
      "Do not remove accepted exact leaves without bit-for-bit and Program identity verification.",
    ]
  JohnnyBtDSL.rules(
    "Read the configuration schema and the host's authoring contract before changing declarations.",
    "Changing accepted values, order or scalar types is a semantic change, not formatting.",
    "Preserve exact numeric values during syntax-only changes; do not hide differences with tolerance.",
    "Configuration declarations collect data; execution algorithms belong to the host.",
    "Custom Ruby validators are runtime-only unless their constraints are represented in the schema.",
    "Unknown or dynamic keys are not implicitly safe to change; validate edited declarations and run owning tests.",
  )
end
