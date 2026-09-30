m = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
puts m[:first]
puts m["last"]
h = m.named_captures
puts h["first"]
puts h["last"]
