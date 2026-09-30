# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

puts "Encoding.aliases: #{Encoding.aliases['BINARY']}"
puts "Encoding.locale_charmap: #{Encoding.locale_charmap.class}"
puts "Encoding._dump: #{Encoding::UTF_8._dump(0)}"
puts "Encoding._load: #{Encoding._load('UTF-8')}"
# CRuby's `_load` answers what it was handed rather than the singleton.
puts "Encoding._load class: #{Encoding._load('UTF-8').class}"

