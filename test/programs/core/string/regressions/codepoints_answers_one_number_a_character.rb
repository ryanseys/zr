# String#codepoints returns an Integer array of UTF-8
# codepoints (not bytes).
puts "hello".codepoints.inspect
puts "あ".codepoints.inspect
puts "".codepoints.inspect
