# Literal backslash preservation — the original bug: "\\n" is two
# bytes (backslash + n) in Ruby source-level escape, and length is 2.
puts "\\n".length     # 2
puts "a\\nb".length   # 4
puts "\\\\".length    # 2

# Standard runtime escape sequences must still work alongside the
# fix — "\n" is one newline byte, "\t" tab, "\r" CR, "\"" quote.
puts "\n".length      # 1
puts "\t".length      # 1
puts "\r".length      # 1
puts "\"".length      # 1
puts "a\nb".length    # 3

# Mixed escapes — literal backslash AND a real newline in the same
# string. "a\\nb\nc" = a, \, n, b, <newline>, c → length 6.
puts "a\\nb\nc".length
