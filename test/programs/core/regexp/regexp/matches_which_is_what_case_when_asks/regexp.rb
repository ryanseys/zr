
m = "hello world".match(/(\w+) (\w+)/)

named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
h = named.named_captures


multiline_str = "abc\ndef"

r = /abc/x




count = 0
"one two three".gsub(/\w+/) { |w| count += 1; w }

puts(/foo/ === "foobar")
puts(/foo/ === "baz")

