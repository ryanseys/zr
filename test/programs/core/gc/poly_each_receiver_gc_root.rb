# `each` over a fresh array that nothing else refers to (the
# `@article.comments` shape -- a new array of records). The loop body
# allocates, and a collection during the loop must keep the array
# alive. The GC.start inside the loop makes that collection occur.
class Box
  def initialize(name); @name = name; end
  def name; @name; end
  def rename(x); @name = x; end   # self-mutating -> heap, not a value type
end

class Bag
  def initialize; @items = []; end
  def add(b); @items.push(b); end

  # Build a FRESH array on every call; the ternary gives two
  # possible return values.
  def items
    fresh = []
    @items.each { |x| fresh.push(x) }
    fresh.empty? ? [] : fresh
  end
end

bag = Bag.new
5.times { |i| bag.add(Box.new("item-" + i.to_s)) }

out = []
bag.items.each do |b|
  GC.start          # collect mid-iteration; unrooted receiver array freed here
  out.push(b.name)
end
puts out.join(",")
