# A Symbol-keyed hash literal passes to a parameter that takes a
# Hash[Symbol, untyped]. This is the roundhouse pattern: render_attrs
# takes any values, and the callers pass a literal with String values.

def render_attrs(attrs)
  pairs = []
  attrs.each do |k, v|
    pairs << k.to_s + "=" + v.to_s
  end
  pairs.join(" ")
end

# Calling with a Symbol-keyed string-valued literal.
puts render_attrs({ class: "primary", id: "go" })

# Calling with the merged form: literal SymStr + LV SymStr.
def build_attrs
  inner = { id: "foo" }
  render_attrs({ class: "btn" }.merge(inner))
end

puts build_attrs
