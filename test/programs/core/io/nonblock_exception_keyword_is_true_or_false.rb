# The exception: keyword of read_nonblock and write_nonblock is true or
# false, as rb_bool_expected checks it; readpartial has no keyword, so a
# Hash is its buffer.
IO.pipe do |r, w|
  [1, nil, "yes", :no].each do |flag|
    begin
      r.read_nonblock(10, exception: flag)
    rescue ArgumentError => e
      p e.message
    end
    begin
      w.write_nonblock("x", exception: flag)
    rescue ArgumentError => e
      p e.message
    end
  end
  p r.read_nonblock(10, exception: false)
  w.write("x")
  p r.read_nonblock(10, exception: false)
  p w.write_nonblock("y", exception: true)
  p r.read_nonblock(10)

  w.write(".")
  begin
    r.readpartial(1, exception: false)
  rescue TypeError => e
    p e.message
  end
  begin
    r.readpartial(1, String.new, exception: false)
  rescue ArgumentError => e
    p e.message
  end
  p r.readpartial(1)
end
