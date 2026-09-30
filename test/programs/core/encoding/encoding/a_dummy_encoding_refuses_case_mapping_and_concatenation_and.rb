%w[UTF-7 UTF-16 ISO-2022-JP IBM037].each do |enc|
  s = "abc".b.force_encoding(enc)
  r = [enc, s.inspect]
  r << (s.upcase rescue [$!.class, $!.message])
  r << (s.downcase rescue [$!.class, $!.message])
  r << ((s + "d") rescue [$!.class, $!.message])
  p r
end
