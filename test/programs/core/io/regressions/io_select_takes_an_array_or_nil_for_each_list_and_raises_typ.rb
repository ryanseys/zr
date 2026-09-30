# Each list that IO.select takes is an Array or nil. A bare IO is a type
# error, not a list of its own lines, so the call never reads the stream.
r, w = IO.pipe
w.write("ready\n")
p((IO.select(r, nil, nil, 0) rescue $!))
p((IO.select(nil, "x", nil, 0) rescue $!))
p((IO.select([], nil, true, 0) rescue $!))
p IO.select([r], nil, nil, 0).map(&:size)
p r.gets
