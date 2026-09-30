# A while condition that depends on a mutated receiver must be evaluated on
# every iteration.

items = [1, 2, 3]
sum = 0

while items.length > 0
  item = items.pop
  sum += item
end

puts sum
puts items.length

items2 = [4, 5, 6]
sum2 = 0

while items2.length > 0
  sum2 += items2.pop
end

puts sum2
puts items2.length

items3 = [7, 8, 9]
packed = 0

while items3.length != 0
  packed = packed * 10 + items3.shift
end

puts packed
puts items3.length

class T_while_condition_recomputed_IvarDrain
  def initialize
    @items = [10, 20, 30]
  end

  def drain
    sum = 0
    while @items.length > 0
      sum += @items.pop
    end
    sum
  end

  def remaining
    @items.length
  end
end

drain = T_while_condition_recomputed_IvarDrain.new
puts drain.drain
puts drain.remaining
