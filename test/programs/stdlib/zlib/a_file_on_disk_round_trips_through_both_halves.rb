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

# A file on disk, through both halves.
show("open round-trip") do
  Zlib::GzipWriter.open("zlib_classes_tmp.gz") { |w| w.write("through a file") }
  Zlib::GzipReader.open("zlib_classes_tmp.gz") { |r| r.read }
ensure
  File.unlink("zlib_classes_tmp.gz")
end

