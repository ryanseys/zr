# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

puts "Array.[]: #{Array[1, 2, 3].inspect}"
puts "Array.[] empty: #{Array[].inspect}"

