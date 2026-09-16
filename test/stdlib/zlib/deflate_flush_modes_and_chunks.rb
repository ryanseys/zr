# The bytes each flush mode writes at each step of a stream, and that
# the way input is cut into calls does not change them.
require "zlib"

def hex(bytes) = bytes.empty? ? "-" : bytes.unpack1("H*")

parts = ["the first part, ", "a second part that repeats the first part, ", "and the last part."]
modes = {
  "NO_FLUSH" => Zlib::NO_FLUSH,
  "SYNC_FLUSH" => Zlib::SYNC_FLUSH,
  "FULL_FLUSH" => Zlib::FULL_FLUSH,
}
modes.each do |name, mode|
  d = Zlib::Deflate.new(6)
  parts.each_with_index do |part, n|
    puts "#{name} step #{n}: #{hex(d.deflate(part, mode))}"
  end
  puts "#{name} finish: #{hex(d.finish)}"
  d.close
end

d = Zlib::Deflate.new(9)
puts "flush(SYNC) on nothing: #{hex(d.flush(Zlib::SYNC_FLUSH))}"
d << "streamed with << "
puts "flush(SYNC): #{hex(d.flush(Zlib::SYNC_FLUSH))}"
puts "flush(FULL) on nothing: #{hex(d.flush(Zlib::FULL_FLUSH))}"
d << "and more"
puts "flush(FINISH): #{hex(d.flush(Zlib::FINISH))}"
d.close

text = ("chunking " * 3000) + ("x" * 70000) + ("chunking " * 100)
whole = Zlib::Deflate.deflate(text, 6)
[1, 7, 100, 4096, 65535, 65536].each do |size|
  d = Zlib::Deflate.new(6)
  out = +""
  text.bytes.each_slice(size) { |slice| out << d.deflate(slice.pack("C*")) }
  out << d.finish
  d.close
  puts "chunks of #{size}: #{out == whole ? "the same bytes" : "different bytes"}"
end
puts "whole: #{whole.bytesize} bytes, crc #{Zlib.crc32(whole)}"

__END__
NO_FLUSH step 0: 789c
NO_FLUSH step 1: -
NO_FLUSH step 2: -
NO_FLUSH finish: 2bc9485548cb2c2a2e5128482c2ad1514854284e4dcecf4b0173154a32124b148a520b52134b8a811c34a5405520b19c44a8901e003bbb1b9f
SYNC_FLUSH step 0: 789c2ac9485548cb2c2a2e5128482c2ad15100000000ffff
SYNC_FLUSH step 1: 4a54284e4dcecf4b0173154a32124b148a520b52134b8a811c54a500000000ffff
SYNC_FLUSH step 2: 4a04aa0289e5244285f400000000ffff
SYNC_FLUSH finish: 03003bbb1b9f
FULL_FLUSH step 0: 789c2ac9485548cb2c2a2e5128482c2ad15100000000ffff
FULL_FLUSH step 1: 4a54284e4dcecf4b5128482c2a5128c9482c51284a2d484d2c2906725215d2328b8a4bc0723a0a00000000ffff
FULL_FLUSH step 2: 4acc4b5128c94855c8492c2e5128482c2ad103000000ffff
FULL_FLUSH finish: 03003bbb1b9f
flush(SYNC) on nothing: 78da000000ffff
flush(SYNC): 2a2e294a4dcc4d4d5128cf2cc950b0b15100000000ffff
flush(FULL) on nothing: 000000ffff
flush(FINISH): 4bcc4b51c8cd2f4a0500784f08f0
chunks of 1: the same bytes
chunks of 7: the same bytes
chunks of 100: the same bytes
chunks of 4096: the same bytes
chunks of 65535: the same bytes
chunks of 65536: the same bytes
whole: 167 bytes, crc 973924618
