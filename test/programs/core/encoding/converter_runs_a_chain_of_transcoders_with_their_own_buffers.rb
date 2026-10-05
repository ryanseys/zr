# A converter is a chain of transcoders, each with its own state
# and buffer, as transcode.c runs it: a character is read whole before
# its bytes go out, a full destination stops between any two bytes, and
# decorators are steps in the chain.
def step(ec, src, dst, size, **opts)
  result = ec.primitive_convert(src, dst, nil, size, **opts)
  p [dst.b, src.b, result]
end

ec = Encoding::Converter.new("UTF-8", "EUC-JP")
src = +"abcあdef"
dst = +""
5.times { step(ec, src, dst, 1) }

ec = Encoding::Converter.new("Shift_JIS", "EUC-JP")
src = "abc\xFFdef".b
dst = +""
5.times { step(ec, src, dst, 10, after_output: true) }

ec = Encoding::Converter.new("", "")
src = +"abcdefg"
dst = +""
2.times { step(ec, src, dst, 2) }

ec = Encoding::Converter.new("UTF-16BE", "UTF-8")
src = "\xD8\x00\x02".b
dst = +""
step(ec, src, dst, 50, partial_input: true)
p ec.primitive_errinfo
ec = Encoding::Converter.new("UTF-16LE", "EUC-JP")
p ec.primitive_convert("\x00\xD8\x21\x00".b, +"", nil, nil), ec.putback(1), ec.putback(1)

ec = Encoding::Converter.new("", "", universal_newline: true)
src = +"a\r"
dst = +""
step(ec, src, dst, 50, partial_input: true)
step(ec, src, dst, 50)

%w[amp_escape xml_text_escape xml_attr_content_escape xml_attr_quote].each do |name|
  ec = Encoding::Converter.new("", name)
  p [name, ec.convert(%q(&<>"')), ec.finish]
end
p Encoding::Converter.new("", "xml_attr_quote").finish

p Encoding::Converter.new(["universal_newline", ["iso-8859-1", "euc-jp"], "universal_newline"]).convpath
p Encoding::Converter.new("UTF-16BE", "UTF-16LE", universal_newline: true).convpath
p Encoding::Converter.search_convpath("ISO-8859-1", "UTF-32BE", universal_newline: true)

ec = Encoding::Converter.new("EUC-JP", "ISO-2022-JP")
dst = +""
ec.primitive_convert("\xA1\xA1".b, dst, nil, 10, partial_input: true)
ec.insert_output("???")
ec.primitive_convert(+"", dst, nil, 10, partial_input: true)
ec.primitive_convert(+"", dst, nil, 10)
p dst.b

ec = Encoding::Converter.new("UTF-8", "ISO-2022-JP", Encoding::Converter::UNDEF_HEX_CHARREF)
p ec.convert("は♥。").b, ec.finish.b
ec = Encoding::Converter.new("EUC-JP", "US-ASCII", Encoding::Converter::UNDEF_HEX_CHARREF)
p ec.convert("\xB8\xF2: n\xA1\xDFm".b.force_encoding("EUC-JP"))
