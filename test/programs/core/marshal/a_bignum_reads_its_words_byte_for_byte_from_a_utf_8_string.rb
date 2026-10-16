# Marshal's words of a Bignum are little-endian bytes. Some pairs of them
# are a valid UTF-8 character ("\xC9\xB0" is U+0270), and a dump kept in
# a UTF-8 String must still read back byte for byte.
p Marshal.load("\x04\bl+\b\xC9\xB0\x81\xBD\x02\x00")
p Marshal.load("\x04\b[\x06l+\b\xC9\xB0\x81\xBD\x02\x00")
p Marshal.load("\x04\bU:\rRational[\al+\b\xC9\xB0\x81\xBD\x02\x00i\x02\xC0\x12")
p Marshal.load("\x04\bl-\b\xE3\x81\x82\xE3\x81\x82")

numbers = [2**64 + 0xB0C9, 0xE38182E38182, -(0xC3A9 << 64), 2**200 + 0xD0B0D0B0, 3**100]
numbers.each do |n|
  text = Marshal.dump([n, { n => -n }]).force_encoding(Encoding::UTF_8)
  p [text.valid_encoding?, Marshal.load(text) == [n, { n => -n }]]
end
