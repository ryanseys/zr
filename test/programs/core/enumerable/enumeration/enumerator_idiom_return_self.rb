# `return to_enum(:each) unless block_given?` ... `self`: with a block, `each`
# answers the receiver; with no block, it answers an Enumerator.
class Box
  include Enumerable
  def each
    return to_enum(:each) unless block_given?

    yield 1
    yield 2
    self
  end
  def to_a2 = each.to_a
end

p Box.new.each.to_a
Box.new.each { |x| p x }
p Box.new.map { |x| x * 3 }
p Box.new.to_a2
p Box.new.each.next
p Box.new.select { |x| x > 1 }
p Box.new.each_with_index.to_a
p Box.new.include?(2)
p Box.new.each.take(1)

# a generator-backed Enumerator answers the span methods by draining first
e = Box.new.each
p [e.take(1), e.drop(1), e.first(2)]
en = Enumerator.new { |y| y << 4; y << 5; y << 6 }
p [en.take(2), en.drop(2)]
