class Odd < Array
  def each
    return to_enum(:each) unless block_given?

    yield 9
    self
  end
end

# enum_each_with_index: the element and its index, and the
# receiver back. An Array that walks as Array does is walked by
# index; anything else is walked by its own `each`.
a = [10, 20]
seen = []
p a.each_with_index { |x, i| seen << [x, i] }.equal?(a)
p seen
p a.each_with_index.to_a
p(a.each_with_index { |x, i| break :b })
p Odd.new([1, 2]).each_with_index.to_a
p (1..3).each_with_index.to_a
p({ x: 1, y: 2 }.each_with_index.to_a)
p [[1, 2]].each_with_index.map { |(x, y), i| [x, y, i] }
