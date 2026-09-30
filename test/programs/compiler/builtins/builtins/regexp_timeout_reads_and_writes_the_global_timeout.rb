# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

puts "Regexp.timeout default: #{Regexp.timeout.inspect}"
Regexp.timeout = 3
puts "Regexp.timeout set: #{Regexp.timeout.inspect}"
Regexp.timeout = nil
puts "Regexp.timeout cleared: #{Regexp.timeout.inspect}"
$_ = "hello world"
puts "Regexp#~: #{~/world/}"
puts "Regexp#~ miss: #{(~/nope/).inspect}"

