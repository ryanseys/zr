# Deflate's bytes at every strategy, window size, memory level and
# wrapper: raw (negative window bits), zlib, and gzip (window bits 16+n,
# whose header carries the OS byte of the platform: 19 on macOS).
require "zlib"

def show(packed) = packed.bytesize <= 48 ? packed.unpack1("H*") : "#{packed.bytesize} bytes, crc #{Zlib.crc32(packed)}"

seed = 777
noise = Array.new(2000) { seed = (seed * 1103515245 + 12345) & 0x7fffffff; (seed >> 16) & 0xff }.pack("C*")
prose = Array.new(1500) { |i| "w#{(i * 13) % 97}" }.join(" ")
text = prose + noise + prose + ("ab" * 3000)

strategies = [Zlib::DEFAULT_STRATEGY, Zlib::FILTERED, Zlib::HUFFMAN_ONLY, Zlib::RLE, Zlib::FIXED]
windows = [-15, -9, 8, 9, 12, 15, 31]
[1, 6, 9].each do |level|
  strategies.each do |strategy|
    windows.each do |wbits|
      [1, 9].each do |mem|
        label = "level #{level} strategy #{strategy} wbits #{wbits} mem #{mem}"
        d = Zlib::Deflate.new(level, wbits, mem, strategy)
        packed = d.deflate(text, Zlib::FINISH)
        d.close
        puts "#{label}: #{show(packed)}"
        # Deflate widens a window of 8 bits to 9, so inflate gets the
        # widest window of the same wrapper.
        i = Zlib::Inflate.new(wbits.negative? ? -15 : wbits > 15 ? 31 : 15)
        raise "no round trip" unless i.inflate(packed) == text
        i.close
      end
    end
  end
end
# A 256-byte window only exists under the zlib wrapper.
[-8, 24].each do |wbits|
  Zlib::Deflate.new(6, wbits)
rescue Zlib::Error => e
  puts "wbits #{wbits}: #{e.class}: #{e.message}"
end
gz = Zlib::Deflate.new(6, 31).deflate("gzip header on record", Zlib::FINISH)
puts "gzip: #{gz.unpack1("H*")}"
puts "os byte: #{gz.getbyte(9)}"

