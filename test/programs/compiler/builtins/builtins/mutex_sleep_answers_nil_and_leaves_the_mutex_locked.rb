# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

m = Thread::Mutex.new
m.lock
puts "Mutex#sleep: #{m.sleep(0.001).inspect}"
puts "Mutex still locked: #{m.locked?}"
m.unlock

