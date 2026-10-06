# A load takes one value from a stream and leaves the rest, so a stream
# holds value after value. A hash whose default is a block cannot be
# written at all, and neither can a module with no name.
require "stringio"
require "tmpdir"

def t = yield rescue [$!.class, $!.message]

io = StringIO.new(+"".b)
Marshal.dump(1, io)
Marshal.dump("two", io)
Marshal.dump([:three], io)
io.rewind
p Marshal.load(io)
p Marshal.load(io)
p Marshal.load(io)
p t { Marshal.load(io) }

path = File.join(Dir.tmpdir, "zr_marshal_stream_#{Process.pid}.bin")
File.open(path, "wb") { |f| Marshal.dump({ "a" => 1 }, f); Marshal.dump("b", f) }
File.open(path, "rb") do |f|
  p Marshal.load(f)
  p Marshal.load(f)
  p f.eof?
end
File.unlink(path)

# A stream that stops in the middle of a value has reached its end;
# bytes that stop there are a dump that was cut short.
full = Marshal.dump("hello")
p t { Marshal.load(StringIO.new(full.byteslice(0, 4))) }
p t { Marshal.load(StringIO.new(full.byteslice(0, 2))) }
p t { Marshal.load(full.byteslice(0, 4)) }
p t { Marshal.load(+"".b) }

p t { Marshal.dump(Hash.new { |h, k| k }) }
p t { Marshal.dump(Hash.new(5)).bytes.last }
p t { Marshal.dump(Object.new.extend(Module.new)) }
p t { Marshal.dump(Class.new.new) }


