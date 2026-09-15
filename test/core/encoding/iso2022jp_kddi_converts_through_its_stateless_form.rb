# ISO-2022-JP-KDDI is stateless-ISO-2022-JP-KDDI's characters between
# escapes, written and read as String#encode and a Converter do.
def t(s, to, **o)
  r = s.encode(to, **o)
  p [r.encoding.name, r.b]
rescue => e
  p [e.class, e.message]
end
k = ->(s) { s.b.force_encoding("ISO-2022-JP-KDDI") }
t "日本a", "ISO-2022-JP-KDDI"
t "a日☀b", "ISO-2022-JP-KDDI"
t "é", "ISO-2022-JP-KDDI", undef: :replace
t "ｱ日", "ISO-2022-JP-KDDI", undef: :replace
t k["\e$B\x21\x21\e(B"], "UTF-8"
t k["a\e$BF|"], "UTF-8"
t k["\e$BF\e(B"], "UTF-8"
t k["\xC3"], "UTF-8"
t k["\e$B\x7F\x21\e(B"], "UTF-8"
t k["\e(Ia\e(B"], "UTF-8"
t k["\e$BF|\e(Jx"], "EUC-JP"
t "\x92\xC6\xFC".b.force_encoding("stateless-ISO-2022-JP-KDDI"), "ISO-2022-JP-KDDI"
t "日".encode("EUC-JP"), "ISO-2022-JP-KDDI"
ec = Encoding::Converter.new("UTF-8", "ISO-2022-JP-KDDI")
p ec.convert("日a").b, ec.finish.b
p Encoding::Converter.new("ISO-2022-JP-KDDI", "UTF-8").convert(k["\e$BF|\e(B"])

__END__
["ISO-2022-JP-KDDI", "\e$BF|K\\\e(Ba"]
["ISO-2022-JP-KDDI", "a\e$BF|uA\e(Bb"]
["ISO-2022-JP-KDDI", "?"]
["ISO-2022-JP-KDDI", "?\e$BF|\e(B"]
["UTF-8", "\xE3\x80\x80"]
["UTF-8", "a\xE6\x97\xA5"]
[Encoding::InvalidByteSequenceError, "\"F\" followed by \"\\e\" on ISO-2022-JP-KDDI"]
[Encoding::InvalidByteSequenceError, "\"\\xC3\" on ISO-2022-JP-KDDI"]
[Encoding::InvalidByteSequenceError, "\"\\x7F\" on ISO-2022-JP-KDDI"]
[Encoding::InvalidByteSequenceError, "\"\\e(\" followed by \"I\" on ISO-2022-JP-KDDI"]
["EUC-JP", "\xC6\xFCx"]
["ISO-2022-JP-KDDI", "\e$BF|\e(B"]
["ISO-2022-JP-KDDI", "\e$BF|\e(B"]
"\e$BF|\e(Ba"
""
"日"
