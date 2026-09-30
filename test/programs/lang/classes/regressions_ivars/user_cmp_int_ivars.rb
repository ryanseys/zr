# A user-defined `def <=>(other)` whose body calls `<=>` on Integer
# ivars (`@n <=> other.n`). The inner `<=>` is Integer#<=>, not a
# recursive call to the user's own method.

class T_user_cmp_int_ivars_V
  attr_reader :n
  def initialize(n)
    @n = n
  end

  def <=>(other)
    @n <=> other.n
  end
end

a = T_user_cmp_int_ivars_V.new(1)
b = T_user_cmp_int_ivars_V.new(2)
c = T_user_cmp_int_ivars_V.new(2)

puts (a <=> b).to_s   # -1
puts (b <=> a).to_s   # 1
puts (b <=> c).to_s   # 0

# Standalone `==` falls back to identity, which doesn't help here.
# This test does not include Comparable.
