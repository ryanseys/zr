# Enumerable's aliases, grep, chunking and slicing over a plain each.
class Bag
  include Enumerable
  def initialize(*items) = @items = items
  def each(&block)
    return to_enum(:each) unless block
    @items.each(&block)
    self
  end
end

b = Bag.new(1, 2, 2, 3, nil, 4, 5)
p b.collect { |x| x }, b.filter { |x| x }, b.find_all { |x| x.nil? }, b.detect { |x| x == 3 }, b.member?(4), b.member?(9), b.compact, b.to_h { |x| [x, x.to_s] }
p b.find(-> { :none }) { |x| x == 9 }, b.detect(-> { :none }) { |x| x == 2 }, b.find { |x| x == 9 }
p b.reverse_each.to_a, b.reverse_each { |x| print x }, b.cycle.first(9), b.cycle(2).class, Bag.new.cycle { }, b.compact.minmax_by { |x| -x }
p b.grep(Integer), b.grep(2..3), b.grep(Integer) { |x| x * 10 }, b.grep_v(Integer), b.grep_v(nil) { |x| x * 2 }, Bag.new("a", :b, "c").grep(String)
p b.compact.chunk_while { |a, c| c == a + 1 }.to_a, b.compact.slice_when { |a, c| c != a }.to_a, b.compact.slice_before { |x| x == 3 }.to_a, b.compact.slice_after { |x| x == 3 }.to_a, b.compact.slice_before(3).to_a, b.compact.slice_after(Integer).to_a
p b.compact.chunk { |x| x.even? }.to_a, b.compact.chunk { |x| x == 3 ? :_alone : x > 3 }.to_a, b.chunk { |x| x.nil? ? :_separator : true }.to_a, b.compact.chunk_while { |a, c| c == a }.map(&:size)
p Bag.new([1, 2], [3, 4]).to_h, Bag.new([1, 2], [3, 4]).each_entry.to_a
p b.to_h { |x| [x, 1] }.size, b.collect.class, b.chunk.class, b.cycle.class, b.reverse_each.class
begin; b.chunk_while; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; b.slice_before; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Bag.new(1).to_h; rescue => e; puts "#{e.class}: #{e.message}"; end
