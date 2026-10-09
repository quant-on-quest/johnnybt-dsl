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
end
