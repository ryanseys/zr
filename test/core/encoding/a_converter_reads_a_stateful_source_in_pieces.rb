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

__END__
[[#<Encoding:ISO-2022-JP (dummy)>, #<Encoding:stateless-ISO-2022-JP>], [#<Encoding:stateless-ISO-2022-JP>, #<Encoding:EUC-JP>], [#<Encoding:EUC-JP>, #<Encoding:UTF-8>]]
"a日"
"本"
""
:finished
"日本x"
""
[:finished, nil, nil, nil, nil]
[[#<Encoding:CP50220 (dummy)>, #<Encoding:CP51932>], [#<Encoding:CP51932>, #<Encoding:UTF-8>]]
"a日"
"本"
""
:finished
"日本x"
""
[:finished, nil, nil, nil, nil]
[[#<Encoding:CP50221 (dummy)>, #<Encoding:CP51932>], [#<Encoding:CP51932>, #<Encoding:UTF-8>]]
"a日"
"本"
""
:finished
"日本x"
""
[:finished, nil, nil, nil, nil]
[[#<Encoding:ISO-2022-JP-KDDI (dummy)>, #<Encoding:stateless-ISO-2022-JP-KDDI>], [#<Encoding:stateless-ISO-2022-JP-KDDI>, #<Encoding:UTF8-KDDI>], [#<Encoding:UTF8-KDDI>, #<Encoding:UTF-8>]]
"a日"
"本"
""
:finished
"日本x"
""
[:finished, nil, nil, nil, nil]
