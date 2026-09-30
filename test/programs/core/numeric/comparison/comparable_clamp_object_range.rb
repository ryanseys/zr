# Comparable#clamp with a one-sided (beginless/endless) or two-sided literal
# Range whose bounds are instances of the receiver's class. A missing side of
# the Range puts no limit on that side.
class Ver
  include Comparable
  attr_reader :n
  def initialize(n); @n = n; end
  def <=>(o); n <=> o.n; end
end

p(Ver.new(12).clamp(..Ver.new(9)).n)             # beginless: clamp down to 9
p(Ver.new(3).clamp(..Ver.new(9)).n)              # beginless: in range, unchanged
p(Ver.new(0).clamp(Ver.new(1)..).n)              # endless: clamp up to 1
p(Ver.new(5).clamp(Ver.new(1)..).n)              # endless: in range, unchanged
p(Ver.new(12).clamp(Ver.new(1)..Ver.new(9)).n)   # two-sided: clamp down
p(Ver.new(0).clamp(Ver.new(1)..Ver.new(9)).n)    # two-sided: clamp up
p(Ver.new(5).clamp(Ver.new(1)..Ver.new(9)).n)    # two-sided: in range

# endless exclusive is fine (no end to apply)
p(Ver.new(0).clamp(Ver.new(1)...).n)

# a two-sided exclusive range cannot clamp -- CRuby raises ArgumentError
begin
  Ver.new(5).clamp(Ver.new(1)...Ver.new(9))
  puts "no raise"
rescue ArgumentError
  puts "excl raised"
end
