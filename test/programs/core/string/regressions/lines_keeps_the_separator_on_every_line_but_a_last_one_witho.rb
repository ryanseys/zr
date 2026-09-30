# Tests String#lines preserves trailing newline on each piece (CRuby semantics).
p "hello\nworld\n".lines
p "hello\nworld".lines
p "single line".lines
p "".lines
p "\n\n\n".lines
puts "hello\nworld\n".lines.length
puts "hello\nworld\n".lines[0]
puts "hello\nworld\n".lines[1]
