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

# -- Deflate/Inflate: the incremental surface -------------------------------

# Failure modes, each its own exception class.
show("not compressed at all") { Zlib::Inflate.inflate("not compressed at all") }
show("truncated stream") { Zlib::Inflate.inflate(Zlib.deflate(TEXT)[0..5]) }
show("trailing garbage") do
  z = Zlib::Inflate.new
  [z.inflate(Zlib.deflate("hi") + "EXTRA"), z.finished?]
end
show("sync_point?") { Zlib::Inflate.new.sync_point? }

