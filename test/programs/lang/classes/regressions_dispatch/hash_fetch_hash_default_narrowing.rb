# Sequel to hash_fetch_hash_default: `params.fetch "k", {}`, then an
# if-expression on `is_a?(Hash)` whose else arm returns an empty Hash.
# Both arms give a Hash, so `sub.is_a?(Hash)` answers true.

class T_hash_fetch_hash_default_narrowing_ArticleParams
  def self.from_raw(params)
    raw_sub = params.fetch "article", {}
    sub = if raw_sub.is_a?(Hash)
      raw_sub
    else
      {}
    end
    sub.is_a?(Hash) ? "got-hash" : "no-hash"
  end
end

puts T_hash_fetch_hash_default_narrowing_ArticleParams.from_raw({ "x" => 1 })
puts T_hash_fetch_hash_default_narrowing_ArticleParams.from_raw({ "y" => 2 })
