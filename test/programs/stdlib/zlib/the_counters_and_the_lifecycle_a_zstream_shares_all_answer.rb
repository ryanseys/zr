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

# The counters and lifecycle `ZStream` shares.
show("counters") do
  z = Zlib::Deflate.new
  z.deflate("hello world", Zlib::FINISH)
  [z.total_in, z.adler, z.data_type, z.avail_in, z.finished?, z.closed?]
end
show("avail_out is a knob") do
  z = Zlib::Deflate.new
  z.avail_out = 100
  z.avail_out
end
# Only the CONTENT is asserted, not whether the queue had anything in it yet:
# zlib emits the 2-byte stream header as soon as `<<` runs, miniz_oxide holds
# it until there is compressed data to go with it. Both produce the same
# stream.
show("flush_next_out drains") do
  z = Zlib::Deflate.new
  z << "hello"
  Zlib::Inflate.inflate(z.flush_next_out + z.finish)
end
show("reset starts over") do
  z = Zlib::Deflate.new
  z.deflate("discarded")
  z.reset
  [Zlib::Inflate.inflate(z.deflate("kept", Zlib::FINISH)), z.total_in]
end
show("close then use") do
  z = Zlib::Deflate.new
  z.finish
  z.close
  [z.closed?, (z.deflate("x") rescue "#{$!.class}")]
end
show("deflate after finish") do
  z = Zlib::Deflate.new
  z.finish
  z.deflate("x")
end
show("finish twice") { z = Zlib::Deflate.new; z.finish; z.finish }

