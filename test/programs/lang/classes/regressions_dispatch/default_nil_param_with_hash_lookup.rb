# `def m(other = nil)` whose body uses `other[key]` (a Hash read with a
# String key). No caller passes a non-nil `other`. The
# `return if other.nil?` guard returns early, so the body keeps
# `@s = nil`, and the attr writer sets the value later.

class T_default_nil_param_with_hash_lookup_Box
  attr_accessor :s

  def initialize(other = nil)
    @s = nil
    return if other.nil?
    v = other["key"]
    @s = v if !v.nil?
  end
end

b = T_default_nil_param_with_hash_lookup_Box.new
b.s = "hello"
puts b.s
