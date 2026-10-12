# Array#permutation with no block returns its enumerator before it reads
# the count (RETURN_SIZED_ENUMERATOR first), and the enumerator's size
# converts the count. combination and repeated_combination read the
# count first. Found by zr-dev fuzz.
def try(label)
  puts "#{label}: #{yield.inspect}"
rescue StandardError => e
  puts "#{label}: #{e.class}: #{e.message}"
end

try("permutation('%d')") { [].permutation("%d") }
try("permutation(2**64)") { ["", "", "", ""].permutation(2**64) }
try("permutation('x').size") { [1].permutation("x").size }
try("permutation(2**64).size") { [1].permutation(2**64).size }
try("permutation('x').to_a") { [1].permutation("x").to_a }
try("permutation(nil)") { [1, 2].permutation(nil) }
try("permutation(nil).size") { [1, 2].permutation(nil).size }
try("permutation(nil) {}") { out = []; [1, 2].permutation(nil) { |p| out << p }; out }
try("permutation(1, 2)") { [1].permutation(1, 2) }
try("permutation(1, 2, 3)") { [1, 2].permutation(1, 2, 3) }
try("permutation(1, 2).size") { [1, 2].permutation(1, 2).size }
try("permutation(1, 2) {}") { [1].permutation(1, 2) {} }
try("permutation.size") { [1, 2, 3].permutation.size }
try("permutation(2).size") { [1, 2, 3].permutation(2).size }
try("permutation(2.9).to_a") { [1, 2, 3].permutation(2.9).to_a }
try("permutation(-1).to_a") { [1, 2].permutation(-1).to_a }
try("permutation(5).to_a") { [1, 2].permutation(5).to_a }
try("repeated_permutation('x')") { [].repeated_permutation("x") }
try("combination('x')") { [].combination("x") }
try("repeated_combination('x')") { [].repeated_combination("x") }
