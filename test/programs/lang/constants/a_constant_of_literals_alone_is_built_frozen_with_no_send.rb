# shareable_constant_value: literal
PATTERNS = [/re/, { p: /q/ }]
p PATTERNS, PATTERNS.frozen?, PATTERNS[1].frozen?
# A constant of literals alone is built frozen, deep, with no send:
# Array#freeze, Hash#freeze and String#freeze redefined see nothing.
class Array; def freeze = raise("Array#freeze called"); end
class Hash; def freeze = raise("Hash#freeze called"); end
class String; def freeze = raise("String#freeze called"); end
FLAT = [1, :a, nil, true, 2.5, -3]
p FLAT, FLAT.frozen?
DEEP = [1, "s", { k: "v", j: [2, :z, "w"] }, __FILE__, 1r]
p DEEP.size, DEEP.frozen?, DEEP[1].frozen?, DEEP[2].frozen?, DEEP[2][:k].frozen?, DEEP[2][:j].frozen?, DEEP[2][:j][2].frozen?, DEEP[3].frozen?
p Ractor.shareable?(DEEP)
p DEEP[1].equal?(DEEP[1]), DEEP[1] == "s"
TABLE = { 1 => :one, two: 2, nil => false }
p TABLE, TABLE.frozen?
EMPTY = []
p EMPTY.frozen?, EMPTY
BIG = [4611686018427387904, 1180591620717411303424]
p BIG, BIG.frozen?, BIG[1].frozen?
SPAN = ("a".."c")
p SPAN, SPAN.frozen?, SPAN.begin.frozen?
# An Array or Hash of immediates outside a constant is a fresh one
# each time, read from the same words.
def fresh = [1, :a, nil, true, 2.5, false]
a = fresh
a << 7
p a, fresh, fresh.frozen?
def pairs = { 1 => :a, b: 2, nil => nil, true => false }
h = pairs
h[:c] = 3
p h, pairs
def empty_hash = {}
p empty_hash, empty_hash.frozen?
