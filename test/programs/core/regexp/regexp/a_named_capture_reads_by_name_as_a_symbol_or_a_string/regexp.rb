
m = "hello world".match(/(\w+) (\w+)/)

named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
puts named[:first]
puts named["last"]
h = named.named_captures
puts h["first"]
puts h["last"]

