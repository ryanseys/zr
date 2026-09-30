# Same shape as the example above — nil-default param, and the body
# uses the param as a Hash — but with a Symbol key.

class T_default_nil_param_with_sym_hash_lookup_Box
  attr_accessor :s
  def initialize(other = nil)
    @s = nil
    return if other.nil?
    v = other[:key]
    @s = v if !v.nil?
  end
end

b = T_default_nil_param_with_sym_hash_lookup_Box.new
b.s = "hello"
puts b.s
