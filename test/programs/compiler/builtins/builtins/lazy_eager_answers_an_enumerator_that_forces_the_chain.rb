# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

puts "lazy eager: #{[1, 2, 3].lazy.map { |x| x * 2 }.eager.class}"
puts "lazy eager values: #{[1, 2, 3].lazy.map { |x| x * 2 }.eager.to_a.inspect}"

