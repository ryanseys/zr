# Enumerable#min and #max compare each element with the best so far as
# `element <=> best`; Array#min and #max send `best <=> element`. An
# error names the receiver's class and the operand.
class Probe
  include Comparable
  attr_reader :n

  def initialize(n) = @n = n
  def inspect = "P#{@n}"

  def <=>(other)
    print "#{inspect}<=>#{other.inspect} "
    n <=> other.n
  end
end

class Each
  include Enumerable

  def initialize(*items) = @items = items
  def each(&) = @items.each(&)
end

items = [Probe.new(1), Probe.new(3), Probe.new(2)]
p Each.new(*items).max
p Each.new(*items).min
p items.max
p items.min
p items.each.max
p Each.new.max, Each.new.min
p Each.new(5).max

def try
  p yield
rescue ArgumentError => e
  puts e.message
end

try { Each.new(2.0, Float::NAN).max }
try { Each.new(2.0, Float::NAN).min }
try { Each.new(Float::NAN, 2.0).max }
try { [2.0, Float::NAN].max }
try { [Float::NAN, 2.0].min }
try { [Float::NAN, 2.0].each.max }
try { Each.new(1, "a").max }
try { [1, "a"].max }
try { { a: 1, b: 2 }.max }
try { Each.new([1, 2], [1, 3]).min }
