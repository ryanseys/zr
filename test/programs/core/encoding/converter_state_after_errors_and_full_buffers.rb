ec = Encoding::Converter.new("utf-8", "iso-8859-1")
p ec.primitive_convert(+"\xf1abcd", +"")
p ec.primitive_convert("glark".dup.force_encoding('utf-8'), +"")
p ec.last_error, ec.primitive_errinfo
ec = Encoding::Converter.new("utf-8", "iso-8859-1")
s = +"\xf1abcd"; dest = +""
p ec.primitive_convert(s, dest), s, ec.primitive_errinfo
p ec.primitive_convert(s, dest), s, dest
ec = Encoding::Converter.new("utf-8", "iso-2022-jp")
p ec.primitive_convert("\u{9999}", +"", 0, 0, partial_input: false)
p ec.primitive_errinfo
