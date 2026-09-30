# Array#&, Array#-, Array#| all dispatch to typed-array intersect /
# difference / union helpers. Each operator's per-shape coverage
# (int / str / float / sym / variable receiver / chained) is
# parallel — one file per operator was duplicating the matrix.
# Element semantics live in test/array_{intersection,difference,union}.rb;
# this file only exercises the operator dispatch path.

# &
puts ([1, 2, 3, 4] & [3, 4, 5]).inspect
puts (["a", "b", "c"] & ["b", "c"]).inspect
puts ([1.0, 2.0, 3.0] & [2.0, 3.0]).inspect
puts ([:a, :b, :c] & [:b, :c]).inspect
amp = [1, 2, 3, 4]
puts (amp & [3, 4, 5]).inspect
puts ([1, 2, 3, 4] & [2, 3, 4] & [3, 4]).inspect

# -
puts ([1, 2, 3, 4] - [2, 4]).inspect
puts (["a", "b", "c"] - ["b"]).inspect
puts ([1.0, 2.0, 3.0] - [2.0]).inspect
puts ([:a, :b, :c] - [:b]).inspect
mns = [1, 2, 3, 4]
puts (mns - [2, 4]).inspect
puts ([1, 2, 3, 4, 5] - [2] - [4]).inspect

# |
puts ([1, 2, 3] | [3, 4, 5]).inspect
puts (["a", "b"] | ["b", "c"]).inspect
puts ([1.0, 2.0] | [2.0, 3.0]).inspect
puts ([:a, :b] | [:b, :c]).inspect
pip = [1, 2, 3]
puts (pip | [3, 4]).inspect
puts ([1, 2] | [2, 3] | [3, 4]).inspect
