p "abc=\r\ndef".unpack("M"), "==41".unpack("M")
p ["x" * 10].pack("m1"), ["g"].pack("H"), ["z"].pack("H*"), ["1"].pack("B16")
p "\x80".unpack("w"), "\x01\x80".unpack("w*"), "abc".unpack("@*a"), "abc".unpack("a@*a")
p "\xED\xA0\x80".unpack("U"), [1, 2].pack("C#c\nC")
["YW=j", "YWI=YWI=", "ab=c"].each do |s|
  s.unpack("m0")
rescue ArgumentError => e
  p e.message
end
[-> { "\xC0\x80".unpack("U") }, -> { "\xC2".unpack("U") }, -> { [1].pack("C_") }, -> { [1].pack("%") }, -> { ["1.5"].pack("d") }, -> { ["1"].pack("w") }].each do |f|
  f.call
rescue ArgumentError, RangeError, TypeError => e
  p [e.class, e.message]
end
begin
  [1].pack("S<>")
rescue RangeError => e
  p e.message
end
