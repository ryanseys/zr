require "digest"

data = (0...4096).map { |i| ((i * 131) + (i >> 5)) & 255 }.pack("C*") * 700
rows = (0..200).map { |n| Digest::SHA256.hexdigest(data.byteslice(0, n))[0, 6] }
rows.each_slice(12) { |row| puts row.join(" ") }
puts Digest::SHA256.hexdigest(data)
digest = Digest::SHA256.new
at = 0
[1, 63, 64, 65, 127, 4096, 100_003].cycle do |take|
  break if at >= data.bytesize

  digest << data.byteslice(at, take)
  at += take
end
puts digest.hexdigest == Digest::SHA256.hexdigest(data)
puts Digest::SHA256.digest("").unpack1("H*")
