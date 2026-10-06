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

# `deflate` hands back what has been FLUSHED so far, which with the default
# NO_FLUSH is usually nothing; `finish` drains the rest.
show("streamed round-trip") do
  z = Zlib::Deflate.new
  parts = [z.deflate("hello "), z.deflate("world"), z.finish]
  Zlib::Inflate.inflate(parts.join)
end
# `<<` queues its output instead of handing it back, so the whole stream
# arrives on the next detaching call.
show("shovel queues") do
  z = Zlib::Deflate.new
  z << "hello " << "world"
  Zlib::Inflate.inflate(z.finish)
end
show("sync flush mid-stream") do
  z = Zlib::Deflate.new
  first = z.deflate("hello", Zlib::SYNC_FLUSH)
  [first.empty?, Zlib::Inflate.inflate(first + z.finish)]
end
show("one-shot class methods") { Zlib::Inflate.inflate(Zlib::Deflate.deflate(TEXT)) == TEXT }
show("compressed encoding") { Zlib::Deflate.deflate("hi").encoding.to_s }
show("inflated encoding") { Zlib::Inflate.inflate(Zlib.deflate("hi")).encoding.to_s }

