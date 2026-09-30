class Two
  def to_int = 2
end
values = [0, 1, -1, 127, 128, 255, 256, -128, -129, 65_535, -32_768, 2**31, -(2**31), 2**32 - 1, 2**62, -(2**62) - 1, 2**63, 2**64 - 1, -(2**63)]
%w[C c S s L l Q q J j n N v V S> s> L> l> Q> q< L_ q!].each do |d|
  packed = values.pack("#{d}*")
  back = packed.unpack("#{d}*")
  puts "#{d.ljust(3)} #{packed.bytesize} #{packed.unpack1('H*')[0, 48]} #{back.first(8).inspect} #{back.last(3).inspect}"
end
p [1, 2.9, Two.new, 2**70, -3].pack("Q<5").unpack("Q<5")
p [1, 2, 3].pack("S2")
p "\x01\x02\x03".unpack("S2")
p "\x01\x02\x03\x04\x05".unpack("L<3")
p "\xff\xff\xff\xff\xff\xff\xff\xff".unpack("Q<q>C2")
p "abc".unpack1("C", offset: 1)
p (0..2000).to_a.pack("L<*").unpack("L<*").sum
begin
  [1].pack("L2")
rescue ArgumentError => e
  p e.message
end
begin
  [nil].pack("L")
rescue TypeError => e
  p e.message
end
