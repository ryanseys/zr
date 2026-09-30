%w[GBK CP949 GB18030 Shift_JIS Big5].each do |enc|
  s = "\xA0z".b.force_encoding(enc)
  s = "\x81z".b.force_encoding(enc) unless s.valid_encoding?
  z = "z".force_encoding(enc)
  p [enc, s.valid_encoding?, s.length, s.index(z), s.include?(z), s.rindex(z)]
end
