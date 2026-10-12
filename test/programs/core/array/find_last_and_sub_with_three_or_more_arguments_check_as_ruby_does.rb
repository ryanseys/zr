# With three or more arguments, ruby's Array#find, #detect and #rfind
# return an enumerator when no block is given, and check 0..1 when one
# is. String#sub and #sub! say that 2 (or 1..2 with a block) are
# expected, and Range#last, #min and #max check their bounds first, then
# say 1, or 0..1 where they go to an Array or to Enumerable. zr takes
# these through two optional parameters, so that a call allocates no
# rest Array, and `Primitive.attr! :more_args` for more.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

a = [3, 8, 5, 10]
try("find(3 args)") { a.find(1, 2, 3) }
try("detect(4 args)") { a.detect(1, 2, 3, 4) }
try("rfind(3 args)") { a.rfind(1, 2, 3) }
try("find(3 args) {}") { a.find(1, 2, 3) { true } }
try("rfind(3 args) {}") { a.rfind(1, 2, 3) { true } }
try("sub(3)") { "hello".sub("l", "L", "x") }
try("sub(3) {}") { "hello".sub("l", "L", "x") { "L" } }
try("sub!(3)") { (+"hello").sub!("l", "L", "x") }
try("(1..3).last(1, 2, 3)") { (1..3).last(1, 2, 3) }
try("('a'..'c').last(1, 2, 3)") { ("a".."c").last(1, 2, 3) }
try("(0...0).last(1, 2, 3)") { (0...0).last(1, 2, 3) }
try("(1..3).max(1, 2, 3)") { (1..3).max(1, 2, 3) }
try("(1..3).min(1, 2, 3)") { (1..3).min(1, 2, 3) }
try("find 3 enum each") { a.find(1, 2, 3).each { |x| x > 4 } }
try("sub!(3) frozen") { "x".freeze.sub!(1, 2, 3) }
try("sub(5) bt") { begin; "x".sub(1, 2, 3, 4, 5); rescue => e; e.backtrace_locations.map(&:label).first(2); end }
try("(1..).max(1,2,3)") { (1..).max(1, 2, 3) }
try("(..1).min(1,2,3)") { (..1).min(1, 2, 3) }
try("(1..).min(1,2,3){}") { (1..).min(1, 2, 3) {} }
try("(1..3).min(1,2,3){}") { (1..3).min(1, 2, 3) {} }
try("(1.0..2.0).max(1,2,3)") { (1.0..2.0).max(1, 2, 3) }
try("('a'...'c').max(1,2,3)") { ("a"..."c").max(1, 2, 3) }
try("(1..).last(1,2,3)") { (1..).last(1, 2, 3) }
try("(1.0..2.0).last(1,2,3)") { (1.0..2.0).last(1, 2, 3) }
try("(..3).last(1,2,3)") { (..3).last(1, 2, 3) }
try("send find") { a.send(:find, 1, 2, 3) }
try("method find") { a.method(:find).call(1, 2, 3) }
try("splat find") { args = [1, 2, 3]; a.find(*args) }
try("kw find") { a.find(1, 2, k: 3) }
try("2 args find") { [a.find(1, 2), (a.find(1, 2) {} rescue $!.message)] }
class Sub < Array; end
try("subclass") { Sub[1].rfind(1, 2, 3).inspect }
