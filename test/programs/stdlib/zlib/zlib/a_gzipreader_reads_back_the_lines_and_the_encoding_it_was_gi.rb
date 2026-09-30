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

show("reader read") { Zlib::GzipReader.new(StringIO.new(GZ)).read }
show("reader read encoding") { Zlib::GzipReader.new(StringIO.new(GZ)).read.encoding.to_s }
show("reader read(n) encoding") { Zlib::GzipReader.new(StringIO.new(GZ)).read(3).encoding.to_s }
show("reader read(n)") do
  r = Zlib::GzipReader.new(StringIO.new(GZ))
  [r.read(3), r.read(3), r.read(100), r.read(3), r.read]
end
show("reader gets") do
  r = Zlib::GzipReader.new(StringIO.new(GZ))
  [r.gets, r.lineno, r.gets, r.gets]
end
show("reader gets with a separator") do
  r = Zlib::GzipReader.new(StringIO.new(GZ))
  [r.gets("o"), r.gets(nil)]
end
show("reader readlines") { Zlib::GzipReader.new(StringIO.new(GZ)).readlines }
show("reader each_line") { Zlib::GzipReader.new(StringIO.new(GZ)).each_line.to_a }
show("reader each is Enumerable's") { Zlib::GzipReader.new(StringIO.new(GZ)).map(&:chomp) }
show("reader chars and bytes") do
  r = Zlib::GzipReader.new(StringIO.new(GZ))
  [r.getc, r.getbyte, r.readchar, r.readbyte]
end
show("reader each_byte") { Zlib::GzipReader.new(StringIO.new(Zlib.gzip("ab"))).each_byte.to_a }
show("reader each_char") { Zlib::GzipReader.new(StringIO.new(Zlib.gzip("ab"))).each_char.to_a }
show("reader ungetc") do
  r = Zlib::GzipReader.new(StringIO.new(GZ))
  c = r.getc
  r.ungetc(c)
  r.gets
end
show("reader readpartial") { Zlib::GzipReader.new(StringIO.new(GZ)).readpartial(4) }
show("reader eof and pos") do
  r = Zlib::GzipReader.new(StringIO.new(GZ))
  before = r.eof?
  r.read
  [before, r.pos, r.eof?, r.eof]
end
show("reader readline past the end") do
  r = Zlib::GzipReader.new(StringIO.new(GZ))
  r.read
  r.readline
end
show("reader rewind") do
  r = Zlib::GzipReader.new(StringIO.new(GZ))
  r.read
  r.rewind
  r.gets
end
show("reader unused") do
  r = Zlib::GzipReader.new(StringIO.new(GZ + "EXTRA"))
  r.read
  r.unused
end
show("reader external_encoding") { Zlib::GzipReader.new(StringIO.new(GZ)).external_encoding.to_s }
show("reader wrap") { Zlib::GzipReader.wrap(StringIO.new(GZ)) { |r| r.read } }
show("reader zcat") { Zlib::GzipReader.zcat(StringIO.new(GZ + GZ)) }
show("reader crc after reading") do
  r = Zlib::GzipReader.new(StringIO.new(GZ))
  r.read
  r.crc == Zlib.crc32("hello\nworld\n")
end

