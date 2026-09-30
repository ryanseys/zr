# A Hash constant passed to a parameter that defaults to `{}`. Two checks:
# the loop runs once for each entry, and each write goes into @units.
#
# `each` on a String-keyed hash runs the block for each pair.
#
# The `@units = {}` literal gets String keys. The literal itself has no keys,
# so its keys have the type of the keys that the code writes into it.
class Quantity
  attr_reader :units
  def initialize(units = {})
    @units = {}
    units.each { |u, e| @units[u] = e }
  end
end
KILO = { 'kg' => 1 }
p Quantity.new(KILO).units
p Quantity.new({ 'g' => 2, 'mg' => 3 }).units
p Quantity.new.units

SYMS = { a: 1 }
p Quantity.new(SYMS).units

INTS = { 1 => 'one' }
p Quantity.new(INTS).units

# the plain function shape, and the iteration count itself
def count(src = {})
  n = 0
  src.each { |k, v| n += 1 }
  n
end
p count(KILO)
p count(SYMS)
p count(INTS)
p count({ 'x' => 1, 'y' => 2 })
p count

# every hash kind through a poly each
def keys_of(src = {})
  out = []
  src.each { |k, v| out << k }
  out
end
p keys_of({ 'a' => 'b' })
p keys_of({ 1 => 2 })
p keys_of({ 1 => 'x' })
p keys_of({ a: [1] })
