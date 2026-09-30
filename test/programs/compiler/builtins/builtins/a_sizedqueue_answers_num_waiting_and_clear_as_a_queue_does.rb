# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

sq = Thread::SizedQueue.new(2)
puts "SizedQueue num_waiting: #{sq.num_waiting}"
sq << 1
puts "SizedQueue clear: #{sq.clear.class}"

