# A value that `is_a?(Hash)` checks goes to a param that also gets a
# Hash literal. `render` reads the key from each Hash.

class T_isa_hash_narrow_typed_param_Bag
  def render(hash)
    hash["k"]
  end

  def visit(table)
    seed = { "k" => "v" }
    render(seed)

    val = table["inner"]
    if val.is_a?(Hash)
      render(val)
    else
      "default"
    end
  end
end

b = T_isa_hash_narrow_typed_param_Bag.new
puts b.visit({ "inner" => { "k" => "tokyo" } })
