# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

puts "attached_object: #{String.singleton_class.attached_object}"
begin
  Class.new.attached_object
rescue TypeError => e
  puts "attached_object plain: #{e.message.sub(/0x\h+/, '0xADDR')}"
end

