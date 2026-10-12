# With three or more arguments, ruby's Array#find, #detect and #rfind
# return an enumerator when no block is given, and check 0..1 when one
# is. String#sub and #sub! say that 2 (or 1..2 with a block) are
# expected, and Range#last says 1, or 0..1 for a range that it makes an
# Array of. zr takes these through two optional parameters, so that a
# call allocates no rest Array, and raises "expected 0..2" for a third
# argument. Up to two arguments match ruby
# (test/programs/core/array/find_rfind_and_each_line_without_a_block_take_any_arguments.rb).
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
