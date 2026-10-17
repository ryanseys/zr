# IO.pipe yields its two ends as one Array, so a block of one parameter
# gets both, and a block of two gets each end.
IO.pipe { |pair| p pair.class, pair.size, pair.map(&:class) }
IO.pipe { |r, w| w.write("hi"); w.close; p r.read }
p IO.pipe { |*all| all.size }
p IO.pipe { |r, | r.class }
p IO.pipe { it.size }
pair = IO.pipe
p pair.size
pair.each(&:close)
