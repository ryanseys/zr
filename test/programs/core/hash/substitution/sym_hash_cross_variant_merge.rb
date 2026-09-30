# Hash#merge between a Symbol-keyed hash of Strings and a Symbol-keyed
# hash of mixed values works in both directions, and returns a new hash.

def dir1_str_recv_poly_arg(t)
  poly = { method: :delete, id: 42, text: t }
  str  = { class: "btn", role: "button" }
  str.merge(poly)
end

def dir2_poly_recv_str_arg(t)
  poly = { method: :delete, id: 42, text: t }
  str  = { class: "btn", role: "button" }
  poly.merge(str)
end

# Both directions: receiver has 2 keys, arg has 3 keys, no
# overlap -> 5 entries in the merged hash.
puts dir1_str_recv_poly_arg("a").length
puts dir2_poly_recv_str_arg("a").length

# Overlap: arg's value wins (standard Hash#merge semantics).
def overlap_dir1
  base = { class: "btn", id: 1 }
  over = { id: 99, name: :foo }
  base.merge(over)[:id]
end
p overlap_dir1
