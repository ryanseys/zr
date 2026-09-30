# ungetc takes a String or a code point in the read encoding, as an
# unsigned int; ungetbyte takes a byte modulo 256, and nil puts back
# nothing. Both need a stream that reads.
def pipe(data)
  r, w = IO.pipe
  w.write(data)
  w.close
  r
end
[-1, 2**32, -2**31, -2**31 - 1, :x, nil, 0xe9, "é"].each do |c|
  r = pipe("ab")
  p [(r.ungetc(c) rescue $!), (r.getc rescue $!)]
end
r = pipe("ab")
p [r.ungetbyte(0x141), r.getc, r.ungetbyte(nil), r.ungetbyte("xy"), r.read]
_, w = IO.pipe
p((w.ungetc("a") rescue $!))
