# zlib's class surface: the incremental `ZStream` pair and the IO-shaped gzip
# pair. Nothing here prints a timestamp or a whole compressed buffer -- gzip
# headers carry the current time, and deflate output is only guaranteed to
# ROUND-TRIP, not to be byte-identical across zlib implementations.
require "zlib"
require "stringio"

def show(label)
  print "#{label}: "
  p(yield)
rescue => e
  puts "#{e.class}: #{e.message}"
end

TEXT = "the quick brown fox jumps over the lazy dog. " * 4

# -- GzipWriter/GzipReader --------------------------------------------------

GZ = Zlib.gzip("hello\nworld\n")

show("writer round-trip") do
  io = StringIO.new("".b)
  w = Zlib::GzipWriter.new(io)
  w.write("hello ")
  w << "world"
  w.close
  Zlib.gunzip(io.string)
end
show("writer close answers the io") do
  io = StringIO.new("".b)
  Zlib::GzipWriter.new(io).close.equal?(io)
end
show("writer wrap answers the block") do
  io = StringIO.new("".b)
  value = Zlib::GzipWriter.wrap(io) { |w| w.write("wrapped"); 42 }
  [value, Zlib.gunzip(io.string)]
end
show("writer header fields") do
  io = StringIO.new("".b)
  w = Zlib::GzipWriter.new(io)
  w.mtime = 1234567890
  w.orig_name = "f.txt"
  w.comment = "a note"
  w.write("x")
  w.close
  r = Zlib::GzipReader.new(StringIO.new(io.string))
  [r.orig_name, r.comment, r.mtime.to_i, r.os_code, r.read]
end
show("writer header is sealed by the first write") do
  io = StringIO.new("".b)
  w = Zlib::GzipWriter.new(io)
  w.write("x")
  w.orig_name = "too late"
end
show("writer print surface") do
  io = StringIO.new("".b)
  w = Zlib::GzipWriter.new(io)
  w.puts("a")
  w.print("b", "c")
  w.printf("%03d", 7)
  w.putc(?Z)
  w.close
  Zlib.gunzip(io.string)
end
show("writer pos and write") do
  io = StringIO.new("".b)
  w = Zlib::GzipWriter.new(io)
  n = w.write("hello")
  r = [n, w.pos, w.tell, w.crc, w.to_io.equal?(io), w.closed?]
  w.close
  r << w.closed?
end
show("writer level in the header") do
  io = StringIO.new("".b)
  Zlib::GzipWriter.wrap(io, Zlib::BEST_COMPRESSION) { |w| w.write(TEXT) }
  Zlib::GzipReader.new(StringIO.new(io.string)).level
end
show("writer accessors after close") do
  io = StringIO.new("".b)
  w = Zlib::GzipWriter.new(io)
  w.close
  w.crc
end

