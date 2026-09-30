# A Converter reads a stateful source a piece at a time: an escape in one
# piece sets how the bytes of the next one read.
%w[ISO-2022-JP CP50220 CP50221 ISO-2022-JP-KDDI].each do |name|
  ec = Encoding::Converter.new(name, "UTF-8")
  p ec.convpath
  p ec.convert("a\e$BF|".b)
  p ec.convert("K\\\e(B".b)
  p ec.finish
  src = +"\e$BF|K\\\e(Bx\e$B".b
  dst = +""
  ec = Encoding::Converter.new(name, "UTF-8")
  p ec.primitive_convert(src, dst), dst, src, ec.primitive_errinfo
rescue => e
  p e
end

