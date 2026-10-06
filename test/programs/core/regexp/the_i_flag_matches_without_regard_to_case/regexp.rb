
m = "hello world".match(/(\w+) (\w+)/)

named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
h = named.named_captures

puts "HELLO".match?(/hello/i)
puts "HELLO".match?(/hello/)

