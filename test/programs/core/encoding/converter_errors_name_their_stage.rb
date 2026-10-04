# A converter names the stage of its path where an error happens, in
# the transcoder's own names (Encoding::Converter).
def t(s, d, str)
  ec = Encoding::Converter.new(s, d)
  begin
    ec.convert(str)
    ec.finish
  rescue => e
    p [e.class, e.message, e.source_encoding_name, e.destination_encoding_name, (e.error_char rescue e.error_bytes)]
  end
  p ec.primitive_errinfo
end
t("iso-8859-1", "big5", "\xe9".force_encoding("iso-8859-1"))
t("euc-jp", "iso-8859-1", "\xa4".force_encoding("euc-jp"))
t("utf-8", "iso-8859-1", "颙")
t("utf-16le", "iso-8859-1", "\x00\xd8a\x00".force_encoding("utf-16le"))
t("euc-jp", "iso-8859-1", "\xa4\xa2".force_encoding("euc-jp"))
ec = Encoding::Converter.new("utf-8", "iso-8859-1")
p ec.primitive_convert("\xf1a".b.force_encoding("utf-8"), +"")
p ec.primitive_errinfo
o = Object.new
def o.to_int = 0
ec = Encoding::Converter.new("utf-8", "iso-8859-1")
dst = +"xyz"
p ec.primitive_convert(+"ab", dst, o, 10), dst
r = Object.new
def r.to_str = "?"
p Encoding::Converter.new("utf-8", "iso-8859-1", undef: :replace, replace: r).replacement
