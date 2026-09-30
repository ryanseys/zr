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

# Window bits pick the container, and are the reason `Net::HTTP` can decode a
# body before it knows which encoding arrived.
show("raw deflate") do
  raw = Zlib::Deflate.new(9, -Zlib::MAX_WBITS).deflate("hi", Zlib::FINISH)
  [raw[0].unpack1("C"), Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(raw)]
end
show("gzip via window bits") do
  gz = Zlib::Deflate.new(9, 16 + Zlib::MAX_WBITS).deflate("hi", Zlib::FINISH)
  [gz.bytes.first(2), Zlib.gunzip(gz)]
end
show("auto-detect gzip") { Zlib::Inflate.new(32 + Zlib::MAX_WBITS).inflate(Zlib.gzip("hello")) }
show("auto-detect zlib") { Zlib::Inflate.new(32 + Zlib::MAX_WBITS).inflate(Zlib.deflate("hello")) }
show("split across writes") do
  gz = Zlib.gzip(TEXT)
  z = Zlib::Inflate.new(32 + Zlib::MAX_WBITS)
  out = +""
  gz.each_byte { |b| out << z.inflate(b.chr) }
  out == TEXT
end

