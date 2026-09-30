# `"hello"[20]` (single-int index past the end) returns nil in CRuby,
# not "". So a `.nil?` check (or any `== nil` comparison) answers true.
puts "hello"[20].nil?     # true
puts "hello"[5].nil?      # true (at end of string, single-int index)
puts "hello"[0].nil?      # false (in bounds)
puts "hello"[4].nil?      # false (last char)
puts "hello"[0]           # "h"
puts "hello"[4]           # "o"
puts "hello"[-1]          # "o" (negative index normalizes)
puts "hello"[-99].nil?    # true (past start)
