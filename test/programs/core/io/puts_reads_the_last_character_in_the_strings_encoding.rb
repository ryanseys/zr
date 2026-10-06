# puts adds a newline unless the last character is one, read in the
# string's own encoding: a 0x0A byte inside a wide character is not.
r, w = IO.pipe
w.binmode
w.puts(0x010a.chr(Encoding::UTF_32BE))
w.puts(0x010a.chr(Encoding::UTF_16BE))
w.puts(0x0a01.chr(Encoding::UTF_32LE))
w.puts(0x0a01.chr(Encoding::UTF_16LE))
w.puts("x\n".encode(Encoding::UTF_16LE))
w.puts("y\n".encode(Encoding::UTF_32BE), "z")
w.puts(["a\n".encode(Encoding::UTF_16BE), 0x010a.chr(Encoding::UTF_16BE)])
w.puts("é\n", "é", "\xff\n".b, "")
w.close
p r.read.b
