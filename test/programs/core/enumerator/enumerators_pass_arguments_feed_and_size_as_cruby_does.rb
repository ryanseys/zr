# Enumerator, Generator, Chain, Product and ArithmeticSequence: each
# with arguments, feed, sizes, rewind and inspect as CRuby gives them.
def show(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end
o = Object.new
def o.each_with_arguments(*args) = yield(args)
e = o.to_enum(:each_with_arguments, :arg0, :arg1)
show(1) { a = []; e.each(:each0, :each1) { |x| a << x }; a }
show(2) { e.each(:each0).to_a }
show(3) { g = Enumerator::Generator.new { |y, *args| y << args; y << 1 }; a = []; g.each(:x, :y) { |v| a << v }; a }
sz = Object.new; def sz.call = 42
show(4) { Enumerator.new(sz) { }.size }
show(5) { en = [1, 2, 3].each; en.feed(:a) rescue $!; r = []; x = [1, 2].map { |v| v }; nil }
show(6) do
  r = []
  en = Enumerator.new { |y| r << y.yield(1); r << y.yield(2); r << y.yield(3) }
  en.feed(:a)
  en.next; en.next; en.next
  r
end
show(7) { en = [1, 2].each; en.next; en.feed(1); en.feed(2) }
show(8) { y = Enumerator::Yielder.allocate; y.send(:initialize) { }.equal?(y) }
show(9) { Enumerator::Chain.allocate.inspect }
show(10) { Enumerator::Product.allocate.inspect }
rw = Object.new; def rw.each = yield(1); def rw.rewind = (puts "rewind"; self)
show(11) { Enumerator::Chain.new(rw, [2]).rewind; :done }
show(12) { c = Enumerator::Chain.new([1], rw); c.each { }; c.rewind; :done }
show(13) { Enumerator::Product.new([1, 2], [3, 4]).each.size }
nan = Object.new; def nan.each_entry = nil; def nan.size = Float::NAN
show(14) { Enumerator::Product.new([1], nan).size }
two = Object.new; def two.each_entry = nil; def two.size = 2.0
show(15) { Enumerator::Product.new([1], two).size }
show(16) { p = Enumerator::Product.new([1]); p.send(:initialize_copy, p).equal?(p) }
show(17) { Enumerator::Product.new([1]).send(:initialize_copy, Enumerator::Product.allocate) }
show(18) { Enumerator::ArithmeticSequence.new }
show(19) { Enumerator::ArithmeticSequence.allocate }
show(20) { Enumerator::Lazy.new([1], -> { 200 }) { }.size }
show(21) { 1.step(10, 3).size }
