# The long tail: one row apiece across Array, Class, Dir, Encoding,

# Enumerator::Lazy, GC, Hash, Marshal, Process, Random, Regexp, Set, String,
# Symbol, Warning and the Thread family.

require "set"
require "tmpdir"

marked = Hash.ruby2_keywords_hash({ a: 1 })
puts "ruby2_keywords_hash: #{marked.inspect}"
puts "ruby2_keywords_hash? plain: #{Hash.ruby2_keywords_hash?({})}"

