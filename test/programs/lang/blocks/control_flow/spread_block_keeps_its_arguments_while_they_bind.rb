# A block that spreads a lone argument over its parameters reads the
# Array `to_ary` answered while its parameters bind, and a default or
# a destructuring parameter runs Ruby in between: the Array stays
# alive across a collection, and a default that changes it changes
# nothing the block was called with, as ruby copies the arguments
# before any default runs.

class Fresh
  def to_ary = [1, 2]
end

def each_fresh
  yield Fresh.new
end

out = each_fresh { |a, b = (GC.start; "x" * 100_000; :default), c| [a, b, c] }
p out

class Shared
  attr_reader :items
  def initialize = @items = [1, 2]
  def to_ary = @items
end

shared = Shared.new
p each_fresh { |a, b = (shared.items.concat([0] * 10_000); :grown), c| [a, b, c] }.tap { shared.items.replace([1, 2]) }
p each_fresh { |a, b = (shared.items[1] = :changed; :written), c| [a, b, c] }.tap { shared.items.replace([1, 2]) }
p each_fresh { |a, b = (shared.items.clear; :cleared), c| [a, b, c] }.tap { shared.items.replace([1, 2]) }

# A destructured first parameter whose `to_ary` grows the Array the
# block spreads, then the parameters after it.
class Growing
  def initialize(items) = @items = items
  def to_ary
    @items.concat([0] * 10_000)
    [:x, :y]
  end
end

def yield_growing
  items = [nil, 2, 3]
  items[0] = Growing.new(items)
  yield items
end

p yield_growing { |(x, y), c, d| [x, y, c, d] }

