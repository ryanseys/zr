# append_as_bytes adds bytes and never changes the encoding, so ASCII
# bytes can break a String in a wide encoding (UTF-16, UTF-32), and the
# String then says it is not valid.
$stdout.sync = true
[Encoding::UTF_32LE, Encoding::UTF_32BE, Encoding::UTF_16LE, Encoding::UTF_16BE].each do |enc|
  str = "abc".encode(enc)
  p [enc, str.valid_encoding?]
  str.append_as_bytes("d")
  p [str.encoding, str.valid_encoding?, str.bytesize]
  str.append_as_bytes("\0" * (enc.name.include?("32") ? 3 : 1))
  p [str.valid_encoding?, str.bytesize]
  str.append_as_bytes(0x61)
  p [str.valid_encoding?, str.bytesize]
end
s = "abc"
s.append_as_bytes("def", 0x67)
p [s, s.encoding, s.valid_encoding?]
b = "".b
b.append_as_bytes("€")
p [b.encoding, b.bytesize, b.valid_encoding?]
u = +"é"
u.append_as_bytes(0xFF)
p [u.encoding, u.valid_encoding?]
