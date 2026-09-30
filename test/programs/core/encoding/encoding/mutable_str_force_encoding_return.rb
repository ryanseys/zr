# A method whose last expression is `force_encoding` (or encode / b) on
# a mutable String built with `String.new` and `<<` returns that String.

def build_via_mutable
  out = String.new
  out << "ab"
  out << "cd"
  out.force_encoding("UTF-8")
end

puts build_via_mutable
