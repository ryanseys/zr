# chomp: takes "\n" and one "\r" before it, a paragraph's "\n\n", or the
# given separator, and only from a line that ends with it.
def pipe(data)
  r, w = IO.pipe
  w.write(data)
  w.close
  r
end
p pipe("a\r").gets(chomp: true)
p pipe("a\nb").gets(nil, chomp: true)
p pipe("a\n\n\nb\n\nc").each_line("", chomp: true).to_a
p pipe("a\n").each_line("", chomp: true).to_a
p pipe("a\r\r\n").each_line(chomp: true).to_a
p pipe("axyb").each_line("xy", chomp: true).to_a
p pipe("abc\n").each_line(3, chomp: true).to_a
p pipe("ab\r\n").each_line(3, chomp: true).to_a
p pipe("a\r\nb\r\n").each_line("\n", chomp: true).to_a
