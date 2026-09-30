# PreExecutionNode -- `BEGIN { ... }`.
#
# CRuby runs all BEGIN blocks in source order, BEFORE any other
# top-level statements, regardless of where they appear in the file.

puts "middle"

BEGIN {
  puts "first"
}

BEGIN {
  puts "first-2"
}

puts "last"
