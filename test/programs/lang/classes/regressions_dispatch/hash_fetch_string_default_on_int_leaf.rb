# `params.fetch "k", ""` on a Hash[String, Int] (or
# Hash[Symbol, Int]). A hit gives the Integer, and a miss gives the
# empty String default.

class T_hash_fetch_string_default_on_int_leaf_P
  def self.lookup_str(params)
    params.fetch "title", ""
  end

  def self.lookup_sym(params)
    params.fetch :title, ""
  end
end

# Hit path: the Integer at the key.
puts T_hash_fetch_string_default_on_int_leaf_P.lookup_str({ "x" => 1, "title" => 42 })
# Miss path: the empty-string default.
puts T_hash_fetch_string_default_on_int_leaf_P.lookup_str({ "x" => 1 })

# Sym-keyed counterpart.
puts T_hash_fetch_string_default_on_int_leaf_P.lookup_sym({ x: 1, title: 99 })
puts T_hash_fetch_string_default_on_int_leaf_P.lookup_sym({ x: 1 })

# Control: the default has the same class as the values.
class T_hash_fetch_string_default_on_int_leaf_Q
  def self.lookup(params)
    params.fetch "x", 0
  end
end
puts T_hash_fetch_string_default_on_int_leaf_Q.lookup({ "x" => 7 })
puts T_hash_fetch_string_default_on_int_leaf_Q.lookup({ "other" => 1 })
