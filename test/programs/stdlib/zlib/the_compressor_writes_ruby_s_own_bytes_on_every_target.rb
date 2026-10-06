# zlib on every target: the compressor writes ruby's bytes there too.
require "zlib"
text = ("wasm and native agree " * 30) + (0..127).to_a.pack("C*")
[1, 6, 9].each do |level|
  puts "#{level}: #{Zlib::Deflate.deflate(text, level).unpack1("H*")}"
end
raw = Zlib::Deflate.new(6, -15).deflate(text, Zlib::FINISH)
puts "raw: #{raw.bytesize} #{Zlib.crc32(raw)}"
puts Zlib::Inflate.new(-15).inflate(raw) == text

