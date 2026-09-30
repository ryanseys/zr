# The class that a conversion TypeError names must be the class of the value
# it converts. Below, an inner conversion is compiled but never runs (its
# branch is not taken). It must not change the class name in the error that
# the outer conversion raises.
#
# `is_a?` on a namespaced exception must also compare its receiver against
# the named class, not against itself.
module M
  class Alpha; end
  class Beta; end
end

x = M::Beta.new
cond = (ARGV.length > 99)

begin
  p 1.0.quo(cond ? ((1.0.quo(M::Alpha.new) > 0.0) ? x : x) : x)
rescue TypeError => e
  p e.message
end

# The same shape through the Array and Hash protocols, which name a class the
# same way.
begin
  p [1, 2].product(cond ? ((1.0.quo(M::Alpha.new) > 0.0) ? x : x) : x)
rescue TypeError => e
  p e.message
end

begin
  p({ 1 => 2 }.merge(cond ? ((1.0.quo(M::Alpha.new) > 0.0) ? x : x) : x))
rescue TypeError => e
  p e.message
end

# A top-level class is not qualified and never used the buffer, so it was
# right all along -- pinned so a future change cannot take it the other way.
class Plain; end
begin
  p 1.0.quo(Plain.new)
rescue TypeError => e
  p e.message
end

# Two nested classes named in one expression, each keeping its own name.
begin
  p 1.0.quo(M::Alpha.new)
rescue TypeError => e
  p e.message
end
begin
  p 1.0.quo(M::Beta.new)
rescue TypeError => e
  p e.message
end
