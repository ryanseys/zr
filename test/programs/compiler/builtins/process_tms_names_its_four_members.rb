# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

puts "Process::Tms.members: #{Process::Tms.members.inspect}"
puts "Process::Tms.keyword_init?: #{Process::Tms.keyword_init?.inspect}"
tms = Process::Tms[1, 2, 3, 4]
puts "Process::Tms.[]: #{tms.inspect}"
tms.utime = 9.5
puts "Process::Tms writer: #{tms.utime}"
puts "Process::Tms to_a: #{tms.to_a.inspect}"

