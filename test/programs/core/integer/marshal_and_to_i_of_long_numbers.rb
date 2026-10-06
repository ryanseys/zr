# Marshal and String#to_i of numbers with many digits give ruby's values,
# and a power-of-two base converts in time linear in the length.
nums = [2**62, -(2**62), 2**64, 2**64 - 1, -(2**70 + 3), 2**100, 1 << 1000, -(3**500), 2**31, 2**30, -(2**30) - 1]
nums.each { |n| d = Marshal.dump(n); p [d.bytes.size, d.unpack1("H*")[0, 40], Marshal.load(d) == n] }
p Marshal.load(Marshal.dump([2**80, { 2**90 => -(2**90) }]))
t = Time.now
big = 2**1000000 - 1
d = Marshal.dump(big)
p d.bytesize, Marshal.load(d) == big
r = Marshal.load(Marshal.dump(Random.new(big)))
p r.seed == big
$stderr.puts "huge in time: #{Time.now - t < 20}"
p "1234567890abcdef" * 3 == ("1234567890abcdef" * 3).to_i(16).to_s(16)
["ff" * 40, "-7" * 33, "1_0000_0000_0000_0000_0000", "DeadBeef" * 9, "0" * 30 + "1"].each { |s| p [s.to_i(16), s.to_i(2), s.to_i(8), s.to_i(32), (Integer("0x" + s.delete("-_")) rescue :bad)] }
p "1010" * 40 == ("1010" * 40).to_i(2).to_s(2)
long = "1234567890abcdef" * 4
["  -" + long, "+0x" + long, long + "zz", long.scan(/.{4}/).join("_"), long + "_", long + "__1", "0b" + "10" * 40, "0o" + "7" * 30, "0" + "7" * 30, "7" * 30 + "9"].each do |s|
  p [s.to_i(16), s.to_i(0), s.to_i(8), s.to_i(2), s.to_i(36), s.to_i]
end
