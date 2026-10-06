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

# -- Checksums --------------------------------------------------------------

show("crc32") { [Zlib.crc32("abc"), Zlib.crc32, Zlib.crc32("abc", 100)] }
show("adler32") { [Zlib.adler32("abc"), Zlib.adler32] }
show("crc32 continued") { Zlib.crc32("def", Zlib.crc32("abc")) == Zlib.crc32("abcdef") }
