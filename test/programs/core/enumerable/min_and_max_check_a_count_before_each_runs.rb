# Enumerable#min(n) and #max(n) convert and check the count before each
# runs, as rb_nmin_run does, and a count of zero runs nothing. A Range
# with a block goes there too.
def show(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

class Loud
  include Enumerable

  def each
    puts "each"
    yield 3
    yield 1
    yield 2
  end
end

[-2, "l", nil, 0, 1, 2, 2.9].each do |n|
  show("float range min(#{n.inspect}) with a block") { (1.0..2.0).min(n) { |a, b| a <=> b } }
  show("float range max(#{n.inspect}) with a block") { (1.0..2.0).max(n) { |a, b| a <=> b } }
  show("Loud#min(#{n.inspect})") { Loud.new.min(n) }
  show("Loud#max(#{n.inspect})") { Loud.new.max(n) { |a, b| b <=> a } }
  show("Hash#max(#{n.inspect})") { { a: 1, b: 2 }.max(n) }
  show("min_by(#{n.inspect})") { (1.0..2.0).min_by(n) { _1 } }
end
show("too big") { Loud.new.min(2**64) }
show("to_int") { o = Object.new; def o.to_int = 1; Loud.new.min(o) }
