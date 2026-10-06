# IO.select's infinite timeout waits as no timeout does; a negative or a
# NaN one is an error. IO#wait takes no infinite timeout.
p IO.select(nil, nil, nil, 0)
p IO.select(nil, nil, nil, 0.0)
IO.pipe do |r, w|
  w << "x"
  p IO.select([r], nil, nil, Float::INFINITY) == [[r], [], []]
  p IO.select([r], nil, nil, 1) == [[r], [], []]
  p r.wait_readable(1) == r
  [[r, :wait_readable], [w, :wait_writable], [r, :wait]].each do |io, name|
    io.public_send(name, Float::INFINITY)
  rescue RangeError => e
    p [name, e.message]
  end
end
[-1, -0.1, -Float::INFINITY, Float::NAN, "x"].each do |t|
  IO.select(nil, nil, nil, t)
rescue ArgumentError, RangeError, TypeError => e
  p [e.class, e.message]
end
