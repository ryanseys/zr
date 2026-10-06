
m = "hello world".match(/(\w+) (\w+)/)

named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
h = named.named_captures


multiline_str = "abc\ndef"

r = /abc/x



puts "hello world".gsub(/o/, "0")
puts "hello world".sub(/o/, "0")
puts "John Smith".gsub(/(\w+) (\w+)/, '\2 \1')
puts "hello".gsub(/l/) { |match| "[#{match}]" }

