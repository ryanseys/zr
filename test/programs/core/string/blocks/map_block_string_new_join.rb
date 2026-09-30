# `join` on an Array of strings from `String.new` joins their bytes with
# the separator. An empty string gives nothing between the separators.

def make_str(x)
  s = String.new
  s << x.to_s
  s
end

xs = [1, 2, 3]

# The block returns String.new directly.
puts xs.map { |x| String.new }.join(",")

# Block body is a method call returning a mutable String — mirrors the
# real-world action_view/view_helpers pattern where the map block calls
# something like `Views::Articles.article_json(article)` and the result
# is joined with "," to form a JSON fragment.
puts xs.map { |x| make_str(x) }.join("-")

# Single-element (no separator emitted in output).
puts [1].map { |x| make_str(x) }.join(",")
