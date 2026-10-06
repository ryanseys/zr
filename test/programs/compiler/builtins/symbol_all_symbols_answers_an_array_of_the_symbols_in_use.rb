# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

puts "Symbol.all_symbols: #{Symbol.all_symbols.is_a?(Array)}"
puts "Symbol.all_symbols has one: #{Symbol.all_symbols.include?(:all_symbols_probe_sym)}"

