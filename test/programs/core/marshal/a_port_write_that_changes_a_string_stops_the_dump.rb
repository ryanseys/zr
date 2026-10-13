# Marshal.dump to a port writes the buffer out once it holds a stdio
# BUFSIZ, right after a String's length. A write that changes that String
# then stops the dump with "string modified during dump".
str = "a" * 100
writes = 0
writer = Object.new
writer.define_singleton_method(:write) do |s|
  writes += 1
  str.replace("")
  s.bytesize
end
begin
  (0..10_000).each do |i|
    str.replace("a" * 100)
    Marshal.dump(["x" * i, str], writer)
  end
  p :none
rescue RuntimeError => e
  p [e.class, e.message, writes.positive?]
end

# A port that leaves the string alone gets the same bytes as a dump to a
# String, in one or more writes.
out = +""
sink = Object.new
sink.define_singleton_method(:write) { |s| out << s; s.bytesize }
data = ["y" * 3000, { "k" => "v" * 2000 }, :sym, 1.5, [1, 2, 3]]
Marshal.dump(data, sink)
p out == Marshal.dump(data), Marshal.load(out) == data
