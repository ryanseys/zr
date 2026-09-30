
m = "hello world".match(/(\w+) (\w+)/)

named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
h = named.named_captures


puts("line1\nline2" =~ /^line2/)
multiline_str = "abc\ndef"
puts(multiline_str =~ /c.d/)
puts(multiline_str =~ /c.d/m)

