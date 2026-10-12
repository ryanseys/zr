# Enumerable#slice_before and #slice_after take exactly one pattern with
# no block, and none with a block, as enum_slice_before and
# enum_slice_after check them. Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

a = [1, 2, 6, 7, 8, 10]
try("slice_after(a, b)") { [].slice_after([], nil) }
try("slice_after(1, 2, 3)") { a.slice_after(1, 2, 3) }
try("slice_after()") { a.slice_after }
try("slice_after(1) {}") { a.slice_after(1) { true } }
try("slice_after(1, 2) {}") { a.slice_after(1, 2) { true } }
try("slice_before(a, b)") { [].slice_before(nil, 0) }
try("slice_before()") { a.slice_before }
try("slice_before(1) {}") { a.slice_before(1) { true } }
try("slice_before(1, 2) {}") { a.slice_before(1, 2) { true } }
try("Hash#slice_after(1, 2)") { { a: 1 }.slice_after(1, 2) }
try("Range#slice_before(1, 2)") { (1..3).slice_before(1, 2) }
try("slice_after(pattern)") { a.slice_after(:even?.to_proc).to_a }
try("slice_after(Integer)") { a.slice_after(6..7).to_a }
try("slice_after {}") { a.slice_after(&:even?).to_a }
try("slice_before(pattern)") { a.slice_before(6..7).to_a }
try("slice_before {}") { a.slice_before { |x| x > 6 }.to_a }
try("slice_after(nil)") { [nil, 1, nil].slice_after(nil).to_a }
try("strings") { %w[a b # c d # e].slice_after("#").map(&:join) }
