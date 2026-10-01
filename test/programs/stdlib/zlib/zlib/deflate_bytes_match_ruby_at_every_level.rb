# Deflate writes the bytes ruby's zlib 1.3.1 writes, at every level.
# The port in lib/zr/runtime/kernel/zlib_*.rb is held to them byte for byte: a
# short stream is shown whole, a long one by its size and crc.
require "zlib"

def show(packed) = packed.bytesize <= 48 ? packed.unpack1("H*") : "#{packed.bytesize} bytes, crc #{Zlib.crc32(packed)}"

seed = 12345
noise = Array.new(4000) { seed = (seed * 1103515245 + 12345) & 0x7fffffff; (seed >> 16) & 0xff }.pack("C*")
words = %w[alpha beta gamma delta epsilon zeta eta theta]
prose = Array.new(3000) { |i| words[(i * 7 + i / 3) % words.size] }.join(" ")

samples = {
  "empty" => "",
  "one" => "a",
  "run" => "z" * 5000,
  "prose" => prose,
  "noise" => noise,
  "mixed" => prose[0, 2000] + noise[0, 500] + prose[2000, 2000],
  "periodic" => ("abcdefghij" * 7000),
}
levels = [Zlib::DEFAULT_COMPRESSION, *0..9]
samples.each do |name, text|
  levels.each do |level|
    packed = Zlib::Deflate.deflate(text, level)
    puts "#{name} level #{level}: #{show(packed)}"
    raise "#{name} at #{level} does not round trip" unless Zlib::Inflate.inflate(packed) == text
  end
end
puts "every stream round trips"

