# putc writes a String's first character, or the byte NUM2CHR makes of
# anything else; Kernel#putc is $stdout's, which adds no $\. printf with
# no format has too few arguments.
r, w = IO.pipe
p [w.putc(65.5), w.putc("xyz"), w.putc(0x141), (w.putc(nil) rescue $!), (w.putc(:a) rescue $!), (w.putc(2**70) rescue $!)]
w.close
p r.read
p((IO.pipe.last.printf rescue $!))
p((format rescue $!), method(:format).parameters)
$\ = "!"
putc "a"
print "b"
$\ = nil
putc 66
putc "cd"
p(putc(67.9))
