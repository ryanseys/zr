# IO.select parks the thread that asks, so a thread that writes later
# still runs; a reader with bytes in its buffer is ready at once.
r, w = IO.pipe
writer = Thread.new { sleep 0.05; w.write "ab\ncd\n" }
ready = IO.select([r], nil, nil, 5)
p ready.map(&:size), ready[0][0].equal?(r)
writer.join
p r.gets
p IO.select([r], [w], nil, 0).map(&:size)
p IO.select([r], nil, nil, 0)&.first&.size
r2, w2 = IO.pipe
p IO.select([r2], nil, nil, 0.05)
t = Thread.new { IO.select([r2]); :woke }
sleep 0.02
w2.write "x"
p t.value

