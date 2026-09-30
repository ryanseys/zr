# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

puts "top-level Queue: #{Queue.equal?(Thread::Queue)}"
puts "top-level Mutex: #{Mutex.equal?(Thread::Mutex)}"
puts "top-level SizedQueue: #{SizedQueue.equal?(Thread::SizedQueue)}"
puts "top-level ConditionVariable: #{ConditionVariable.equal?(Thread::ConditionVariable)}"
puts "RUBY_COPYRIGHT: #{RUBY_COPYRIGHT.start_with?('ruby - Copyright')}"
puts "File::Separator: #{File::Separator.inspect}"

