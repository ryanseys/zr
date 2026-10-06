# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

str = +"é"
puts "unicode_normalize!: #{str.unicode_normalize!(:nfc).bytes.inspect}"
puts "unicode_normalize! in place: #{str.bytes.inspect}"

