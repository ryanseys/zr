# `$.` is the number of the line the last read took: 0 before any
# read, then what `gets` counts on the stream it read from. A write
# sets it until the next read. `$<` is ARGF.
p $.
p $<.equal?(ARGF), $<.class
r, w = IO.pipe
w.write("a\nb\nc\n")
w.close
r.gets
r.gets
p $., r.lineno
$. = 10
p $.
r.gets
p $.
p r.gets, $.
r.close

