# Three Hash calls on three kinds of hash: merge with a keyword
# argument (Symbol keys, mixed values), dup (String keys, Integer
# values) and fetch (String keys, mixed values). ActionView's
# link_to / button_to / content_for_get use these shapes.

def merge_kwarg(h); h.merge(c: 3); end
m = merge_kwarg({ a: 1, b: "two" })
puts m.length
puts m.has_key?(:a)
puts m.has_key?(:c)

def dup_strint(h); h.dup; end
d = dup_strint({ "a" => 1, "b" => 2 })
puts d.length
puts d["a"]
puts d["b"]

def fetch_strpoly(h, k); h.fetch(k, "miss"); end
hp = { "a" => 1, :b => "two" }
puts fetch_strpoly(hp, "a")
puts fetch_strpoly(hp, "missing")
