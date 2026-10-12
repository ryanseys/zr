# A method with no block returns an enumerator that holds the arguments
# as the call gave them: a Float count is converted for the check but
# shown as given, and a default argument the call left out is not shown.
# Each name of a method has its own entry, so the enumerator names the
# one called. The size counts as ruby_num_interval_step_size does.
def try(label)
  r = yield
  r = [r.inspect, r.size] if r.is_a?(Enumerator)
  puts "#{label}: #{r.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

a = [3, 1, 2]
h = { a: 1, b: 2, c: 3 }
try("String#upto(nil)") { "".upto(nil) }
try("String#upto('c')") { "a".upto("c") }
try("String#upto('c', true)") { "a".upto("c", true) }
try("String#upto('c', nil)") { "a".upto("c", nil) }
try("String#upto('c', false) to_a") { "a".upto("c", false).to_a }
try("String#upto('c', true) to_a") { "a".upto("c", true).to_a }
[1.5, 2r, 2, 2**64].each do |n|
  try("Hash#each_slice(#{n.inspect})") { h.each_slice(n) }
  try("Range#each_cons(#{n.inspect})") { (1..5).each_cons(n) }
  try("Array#combination(#{n.inspect})") { a.combination(n) }
  try("Array#repeated_combination(#{n.inspect})") { a.repeated_combination(n) }
end
try("Hash#each_slice(1.5) to_a") { h.each_slice(1.5).to_a }
try("Range#each_cons(2.9) to_a") { (1..4).each_cons(2.9).to_a }
try("Array#combination(1.5) to_a") { a.combination(1.5).to_a }
try("Hash#each_slice('2')") { h.each_slice("2") }
try("Hash#each_slice(0.5)") { h.each_slice(0.5) }
try("Array#combination('2')") { a.combination("2") }
try("Enumerator#each_with_object") { a.each.each_with_object([]) }
try("Enumerator#with_object") { a.each.with_object([]) }
try("Enumerator#each_with_object {}") { a.each.each_with_object([]) { |x, m| m << x * 2 } }
try("5.downto(2r)") { 5.downto(2r) }
try("5.downto(2.5r)") { 5.downto(2.5r) }
try("5.upto(7.5r)") { 5.upto(7.5r) }
try("5.upto(4r)") { 5.upto(4r) }
try("5.downto(6r)") { 5.downto(6r) }
try("5.downto(2r) to_a") { 5.downto(2r).to_a }
try("1.5.step('2')") { 1.5.step("2") }
try("1.5.step(true)") { 1.5.step(true) }
try("1.step('2', 1.0)") { 1.step("2", 1.0) }
try("1.5.step(Object)") { 1.5.step(Object.new) }
try("1.step(3, 1.0)") { 1.step(3, 1.0) }
try("1.0.step(3)") { 1.0.step(3) }
try("-3.times") { -3.times }
try("0.times") { 0.times }
try("3.times") { 3.times }
try("-(2**70).times") { (-2**70).times }
try("(2**70).times") { (2**70).times }
try("1.upto(3r) {}") { r = []; 1.upto(3r) { r << _1 }; r }
try("5.downto(2.5r) {}") { r = []; 5.downto(2.5r) { r << _1 }; r }
try("1.upto(3.5r) to_a") { 1.upto(3.5r).to_a }
try("1.upto(Object) {}") { 1.upto(Object.new) {} }
try("1.downto(nil) {}") { 1.downto(nil) {} }
try("(2**70).upto(2**70 + 5.5r)") { (2**70).upto(2**70 + 5.5r) }
try("(2**70).downto(2**70 - 2.5r)") { (2**70).downto(2**70 - 2.5r) }
try("(2**70).downto(2**70 - 2.5r) to_a") { (2**70).downto(2**70 - 2.5r).to_a.size }
