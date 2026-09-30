# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

puts "Warning.categories: #{Warning.categories.include?(:deprecated)}"
puts "Warning#warn listed: #{Warning.instance_methods(false).inspect}"

