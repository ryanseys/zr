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

# Corruption. CRuby checks a member's footer only once the buffer it filled
# has been fully handed out, so `read` (which answers everything at once)
# reports nothing and the line-at-a-time readers do -- reproduced faithfully.
def corrupt(offset)
  bad = GZ.dup
  bad.setbyte(bad.bytesize + offset, GZ.getbyte(GZ.bytesize + offset) ^ 0xff)
  bad
end
show("not gzip at all") { Zlib::GzipReader.new(StringIO.new("not gzip at all")) }
show("bad crc via read") { Zlib::GzipReader.new(StringIO.new(corrupt(-8))).read }
show("bad crc via readlines") { Zlib::GzipReader.new(StringIO.new(corrupt(-8))).readlines }
show("bad length via gunzip") { Zlib.gunzip(corrupt(-4)) }
show("bad crc via gunzip") { Zlib.gunzip(corrupt(-8)) }
show("truncated member") { Zlib::GzipReader.new(StringIO.new(GZ[0..15])).read }

