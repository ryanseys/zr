# ruby 4.1 takes a converter's two names from its first and last
# transcoder, as each transcoder declares them (WINDOWS-1252 for
# Windows-1252, SJIS-DOCOMO for the carrier's step). Converter#inspect,
# the error messages and the errors' encoding names show them.
def err
  yield
  :ok
rescue EncodingError => e
  [e.class, e.message, e.source_encoding_name, e.destination_encoding_name]
end

p Encoding::Converter.new("Windows-1252", "UTF-8")
p Encoding::Converter.new("utf-8", "windows-1252")
p Encoding::Converter.new("macRoman", "UTF-8", universal_newline: true)
p Encoding::Converter.new("Windows-1252", "KOI8-R")
p Encoding::Converter.new("SJIS-DoCoMo", "UTF-8")
p Encoding::Converter.new("UTF-8", "SJIS-DoCoMo")
p Encoding::Converter.new("UTF8-DoCoMo", "UTF-8")
p Encoding::Converter.new("UTF8-DoCoMo", "SJIS-DoCoMo")
p Encoding::Converter.new("SJIS-KDDI", "UTF-8")
p Encoding::Converter.new("EUC-JP", "Shift_JIS")
p Encoding::Converter.new([["Windows-1252", "UTF-8"], "universal_newline"])
p Encoding::Converter.new([["UTF-8", "macGreek"]])
p Encoding::Converter.new("", "", universal_newline: true)

p err { "\x81".force_encoding("Windows-1252").encode("UTF-8") }
p err { "щ".encode("Windows-1252") }
p err { "\x81".force_encoding("Windows-1252").encode("KOI8-R") }
p err { "щ".encode("Windows-874") }
p err { "あ".encode("macCyrillic") }
p err { "\xEE\x9A\xA0".force_encoding("UTF8-DoCoMo").encode("UTF8-KDDI") }

ec = Encoding::Converter.new("UTF-8", "Windows-1250")
p ec.primitive_convert(+"あ", +"")
p ec.primitive_errinfo
p ec.last_error&.message
p [ec.source_encoding, ec.destination_encoding]

ec = Encoding::Converter.new("Windows-1252", "UTF-8")
p ec.convert("caf\xE9".force_encoding("Windows-1252"))
p ec.convpath
