# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

q = Thread::Queue.new
q << 1
q << 2
puts "Queue num_waiting: #{q.num_waiting}"
puts "Queue clear: #{q.clear.class}"
puts "Queue size after clear: #{q.size}"
begin
  q.marshal_dump
rescue TypeError => e
  puts "Queue marshal_dump: #{e.message}"
end
begin
  Thread::ConditionVariable.new.marshal_dump
rescue TypeError => e
  puts "CV marshal_dump: #{e.message}"
end

