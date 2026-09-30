# A read takes from the descriptor everything it can and holds what
# the program did not ask for. Those bytes make the stream ready: a
# select that asked the descriptor alone would wait for data that is
# already in hand.
r, w = IO.pipe
w.write "ab"
p r.getc
p IO.select([r], nil, nil, 0)&.first&.map { |io| io.equal?(r) }
p IO.select(nil, [w], nil, 0)&.at(1)&.map { |io| io.equal?(w) }
p r.read(1)
p IO.select([r], nil, nil, 0)
w.write "c"
p IO.select([r], nil, nil, 0)&.first&.size
w.close
p r.read
r.close

