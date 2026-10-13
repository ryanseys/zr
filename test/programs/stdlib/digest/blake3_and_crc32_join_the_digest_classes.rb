# digest 3.3.0 (ruby 4.1): Digest::BLAKE3 (a 32-byte digest over 64-byte
# blocks) and Digest::CRC32 (zlib's CRC-32, four bytes big-endian), both
# Digest::Base classes that the digest library loads on first use.
require "digest"

data = (0...5000).map { |i| (i * 7 % 256).chr }.join.b
[0, 1, 63, 64, 65, 1023, 1024, 1025, 2048, 3000, 4097, 5000].each do |n|
  piece = data.byteslice(0, n)
  p [n, Digest::BLAKE3.hexdigest(piece), Digest::CRC32.hexdigest(piece)]
end

p Digest::BLAKE3.hexdigest("abc")
p Digest::BLAKE3::VERSION, Digest::BLAKE3::LIBRARY_VERSION, Digest::BLAKE3::VERSION.frozen?
p Digest::BLAKE3.superclass, Digest::CRC32.superclass
p Digest::BLAKE3.new.digest_length, Digest::BLAKE3.new.block_length
p Digest::CRC32.new.digest_length, Digest::CRC32.new.block_length
p Digest::CRC32.digest("abc"), Digest::CRC32.new.inspect, Digest::CRC32.hexdigest("")

b = Digest::BLAKE3.new
b.update("ab")
b << "c"
copy = b.dup
p b.hexdigest == Digest::BLAKE3.hexdigest("abc"), copy.hexdigest == b.hexdigest
b << "d"
p b.hexdigest == Digest::BLAKE3.hexdigest("abcd"), copy.hexdigest == Digest::BLAKE3.hexdigest("abc")
p b.digest!.bytesize, b.hexdigest == Digest::BLAKE3.hexdigest("")
c = Digest::CRC32.new
data.each_char.each_slice(333) { |s| c << s.join }
p c.hexdigest == Digest::CRC32.hexdigest(data), c.reset.hexdigest, (c == Digest::CRC32.new)
p Digest::CRC32.file(__FILE__).hexdigest == Digest::CRC32.hexdigest(File.binread(__FILE__))
p Digest::BLAKE3.base64digest("abc")
p Digest::BLAKE3.constants.sort, Digest::CRC32.constants.sort
