# A string literal with an embedded NUL byte reports the full
# length, and .bytes iterates all bytes, also the ones after the NUL.
puts "hello\0world".length
puts "hello\0world".bytes.length
puts "a\0b\0c".length
puts "\0\0\0".length
