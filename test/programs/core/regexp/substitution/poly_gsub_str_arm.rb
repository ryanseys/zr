# `v.gsub(/regex/, "repl")` where v is poly-typed (for example, from
# a poly-valued hash lookup). gsub / sub on a String value answer a
# String.

def normalize(entry)
  v = entry[:stream]
  v.gsub(/[^a-z]/, "_")
end

# Force the hash to be poly-valued by mixing value types — the
# `:stream` value is String, but `:count` is Int, so the analyzer
# widens the hash to sym_poly_hash and `entry[:stream]` returns
# sp_RbVal rather than const char *.
h = { stream: "abc/def", count: 5 }
puts normalize(h)
