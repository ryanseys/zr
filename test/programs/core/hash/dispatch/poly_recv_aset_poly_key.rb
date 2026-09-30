# `merged[k] = v` where the types of merged AND k are known only at
# run time. `[]=` goes to Hash#[]= because merged is a Hash, and the
# key is the String that k holds.

def get_poly(h, key)
  h[key]
end

def write_back(merged, k, v)
  merged[k] = v
end

def run(outer)
  merged = get_poly(outer, "m")
  # k and v come through a helper, so their types are known only
  # at run time.
  pairs = get_poly(outer, "pairs")
  k = get_poly(pairs, "k")
  v = get_poly(pairs, "v")
  write_back(merged, k, v)
  merged["b"]
end

outer = { "m" => { "a" => 1 }, "pairs" => { "k" => "b", "v" => 99 } }
puts run(outer)
