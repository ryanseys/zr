# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

s = Set[1, 2]
puts "compare_by_identity? before: #{s.compare_by_identity?}"
puts "compare_by_identity: #{s.compare_by_identity.class}"
puts "compare_by_identity? after: #{s.compare_by_identity?}"

