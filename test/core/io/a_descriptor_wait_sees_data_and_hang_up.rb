# Waiting on one descriptor: a pipe with nothing in it is not readable,
# data makes it readable but not priority-readable, and a closed write
# end makes it readable too (a read then answers EOF). A pipe's write
# end is writable at once.
r, w = IO.pipe
p IO.select([r], nil, nil, 0)
p IO.select(nil, [w], nil, 0) == [[], [w], []]
w.write("x")
p IO.select([r], nil, nil, 1) == [[r], [], []]
p IO.select(nil, nil, [r], 0)
p r.wait_readable(1) == r
p r.wait_priority(0)
p r.read(1)
p IO.select([r], nil, nil, 0)
w.close
p IO.select([r], nil, nil, 1) == [[r], [], []]
p r.read
r.close

__END__
nil
true
true
nil
true
nil
"x"
nil
true
""
