
m = "hello world".match(/(\w+) (\w+)/)

named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
h = named.named_captures


multiline_str = "abc\ndef"

r = /abc/x

puts "one two three".scan(/\w+/)
puts "a1b2c3".scan(/([a-z])(\d)/)

