# `rows = []` followed by `rows << <container>` (where the pushed
# value is a Hash or another Array, not a primitive). The pushes
# give `rows` its element type, so it holds the containers, the same
# as the literal `[{...}, {...}]` does.

def build_hash_rows
  rows = []
  rows << { "k" => "v" }
  rows << { "k" => "v2" }
  rows.length
end

def build_nested_arrays
  outer = []
  inner = [1, 2]
  outer << inner
  outer << [3, 4]
  outer.length
end

puts build_hash_rows         # 2
puts build_nested_arrays     # 2
