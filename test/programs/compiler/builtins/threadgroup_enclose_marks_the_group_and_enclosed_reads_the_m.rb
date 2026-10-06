# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

g = ThreadGroup.new
puts "ThreadGroup enclosed? before: #{g.enclosed?}"
puts "ThreadGroup enclose: #{g.enclose.class}"
puts "ThreadGroup enclosed? after: #{g.enclosed?}"
puts "Default enclosed?: #{ThreadGroup::Default.enclosed?}"

