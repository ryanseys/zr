# `Hash#fetch(key, {})` on a Hash with Integer values. A hit gives the
# Integer, and a miss gives the empty Hash default.

class T_hash_fetch_hash_default_P
  def self.lookup_present(params)
    params.fetch "x", {}
  end

  def self.lookup_missing(params)
    params.fetch "missing", {}
  end
end

box = { "x" => 7 }
v1 = T_hash_fetch_hash_default_P.lookup_present(box)
v2 = T_hash_fetch_hash_default_P.lookup_missing(box)
# Hit path returns the Integer value
puts v1.is_a?(Integer) ? v1 : "non-int"
# Miss path returns the empty hash
puts v2.is_a?(Hash) ? "hash" : "non-hash"
