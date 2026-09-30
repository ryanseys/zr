# Enumerable methods over enumerators, lazy chains, an each that yields
# to a kept block later, an each written in a module and refined, and
# blocks that break, next, redo-free retry and raise through the
# kernel's each adapter.
class Rows
  include Enumerable
  def initialize(*rows) = @rows = rows
  def each(&b)
    return enum_for(:each) { @rows.size } unless b
    @rows.each(&b)
    self
  end
end
r = Rows.new(1, [2, 3], nil, 4)
p r.each.size, r.each.next, r.lazy.select { |v| v }.map { |v| v.to_s }.first(2), r.each_slice(2).to_a
p r.each_with_index.select { |v, i| i.even? }, r.each.with_object([]) { |v, acc| acc << v.class }, r.min_by { |v| v.to_s.size }
p r.find_index(4), r.find_index { |v| v.nil? }, r.first, r.first(3), r.take(2), r.drop(2), r.include?([2, 3]), r.entries
p r.select.with_index { |v, i| i > 1 }, r.each_entry.to_a.size, r.sort_by { |v| v.to_s }, r.reduce(:to_s) rescue p $!.class
def raising(rows) = rows.select { |v| raise "boom" if v.nil?; v }
p (raising(r) rescue $!.message)
def broken(rows) = rows.each_with_index.to_a.size + rows.count { |v| break 10 if v.nil?; true }
p broken(r)
en = r.each
p en.next, en.next, en.next, en.next, (en.next rescue $!.class), en.rewind.next
p r.zip([1, 2, 3, 4]), r.chunk_while { |a, b| b.nil? }.to_a, r.slice_when { |a, b| b.is_a?(Array) }.to_a, r.tally.size
p r.group_by { |v| v.class }.keys, r.partition { |v| v }, r.each_cons(3).to_a.size, r.flat_map { |v| [v, v] }.size, r.sum { |v| v.is_a?(Integer) ? v : 0 }
p Rows.new.first, Rows.new.min, Rows.new.to_a, Rows.new.each_slice(2).to_a, Rows.new.inject(:+), Rows.new.count
h = { a: 1, b: 2 }
p h.each_with_index.to_a, h.min_by { |k, v| v }, h.find { |k, v| v == 2 }, h.select { |k, v| v > 1 }, h.map { |k, v| k }, h.each_entry.to_a
p (1..Float::INFINITY).lazy.map { |v| v * 2 }.select { |v| v % 3 == 0 }.first(3), (1..4).each_slice(3).to_a, (1..4).inject { |a, b| a * b }

