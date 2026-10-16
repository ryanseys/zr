# read_nonblock takes one or two arguments and any keywords, as
# strio_read_nonblock scans "11:". A write whose end passes a long raises
# ArgumentError, as strio_extend does. set_encoding leaves a chilled
# String's encoding alone, so it does not warn that the literal will be
# frozen.
require "stringio"
Warning[:deprecated] = true

f = StringIO.new("あい")
[-> { f.read_nonblock(-1, exception: false) }, -> { f.read_nonblock(1, 2, 3, exception: false) },
 -> { f.read_nonblock }, -> { f.read_nonblock(1, nil, nil) }, -> { f.read_nonblock(1, exception: false, x: 1) },
 -> { f.read_nonblock(2, +"buf") }, -> { f.read_nonblock(100, exception: false) }, -> { f.read_nonblock(1, exception: false) },
 -> { f.read_nonblock(1) }].each do |c|
  p c.call
rescue => e
  p e
end

g = StringIO.new
g.pos = StringIO::MAX_LENGTH
begin
  g.write("pos + len overflows")
rescue ArgumentError => e
  p e
end
p g.string, g.pos == StringIO::MAX_LENGTH
g.pos = StringIO::MAX_LENGTH - 3
p((g.write("abcd") rescue $!))

chilled = eval(%{""})
io = StringIO.new(chilled)
io.set_encoding(Encoding::BINARY)
p io.string.encoding, io.string.equal?(chilled), io.external_encoding
plain = +"x"
io = StringIO.new(plain)
io.set_encoding(Encoding::BINARY)
p plain.encoding
