# The ISO-2022-JP family converts through its stateless multibyte encoding:
# each run of two-byte characters stands behind its escape, CP50221 holds
# halfwidth katakana as a set of its own and CP50220 writes them fullwidth,
# and each failure names the step of the path it stopped in.
s = "abc日本"
j = s.encode("ISO-2022-JP")
p j.b.unpack1("H*"), j.encoding, j.encode("UTF-8"), "日\n本".encode("ISO-2022-JP").b
p "日本".encode("CP50221").b, "日本".encode("CP50220").b, "ｱｲ日".encode("CP50221").b, "ｱｲ日".encode("CP50220").b
p "ｶﾞｷﾞﾊﾟﾟｳﾞﾞカﾞ".encode("CP50220").force_encoding("CP50220").encode("UTF-8")
p "①".encode("CP50221").b, "日本".encode("EUC-JP").encode("ISO-2022-JP").b
p "\e$BF|\e(B".force_encoding("ISO-2022-JP").encode("EUC-JP").b, "ab\e$BF|".force_encoding("ISO-2022-JP").encode("UTF-8")
p "\e(I12\e(B".force_encoding("CP50221").encode("UTF-8"), "\e(J\\~\e(B".force_encoding("ISO-2022-JP").encode("UTF-8")
p "é".encode("ISO-2022-JP", undef: :replace).b, "é".encode("ISO-2022-JP", invalid: :replace, undef: :replace, replace: "*").b
["é", "\u{1F600}", "ｱ"].each { |c| begin; c.encode("ISO-2022-JP"); rescue => e; p [e.class, e.message, e.error_char, e.source_encoding_name, e.destination_encoding_name]; end }
["\e$B\x7f\x7f\e(B", "\e$Z", "\e$B\nF|", "\e(Ia", "ab\e", "\e$B\x2F\x7E", "\e$BF\x10", "\e$BF", "\x80", "\e("].each do |bad|
  begin
    bad.dup.force_encoding("ISO-2022-JP").encode("UTF-8")
  rescue => e
    p [e.class, e.message]
  end
end
["\e(I\x60", "\x80"].each { |bad| begin; bad.dup.force_encoding("CP50221").encode("UTF-8"); rescue => e; p [e.class, e.message]; end }
p "\e$B".force_encoding("ISO-2022-JP").encode("UTF-8")

__END__
"6162631b2442467c4b5c1b2842"
#<Encoding:ISO-2022-JP (dummy)>
"abc日本"
"\e$BF|\e(B\n\e$BK\\\e(B"
"\e$BF|K\\\e(B"
"\e$BF|K\\\e(B"
"\e(I12\e$BF|\e(B"
"\e$B%\"%$F|\e(B"
"ガギパ゜ウ゛゛カ゛"
"\e$B-!\e(B"
"\e$BF|K\\\e(B"
"\xC6\xFC"
"ab日"
"ｱｲ"
"\\~"
"?"
"*"
[Encoding::UndefinedConversionError, "\"\\x8F\\xAB\\xB1\" to stateless-ISO-2022-JP in conversion from UTF-8 to EUC-JP to stateless-ISO-2022-JP to ISO-2022-JP", "\x{8FABB1}", "EUC-JP", "stateless-ISO-2022-JP"]
[Encoding::UndefinedConversionError, "U+1F600 to EUC-JP in conversion from UTF-8 to EUC-JP to stateless-ISO-2022-JP to ISO-2022-JP", "😀", "UTF-8", "EUC-JP"]
[Encoding::UndefinedConversionError, "\"\\x8E\\xB1\" to stateless-ISO-2022-JP in conversion from UTF-8 to EUC-JP to stateless-ISO-2022-JP to ISO-2022-JP", "\x{8EB1}", "EUC-JP", "stateless-ISO-2022-JP"]
[Encoding::InvalidByteSequenceError, "\"\\x7F\" on ISO-2022-JP"]
[Encoding::InvalidByteSequenceError, "\"\\e$\" followed by \"Z\" on ISO-2022-JP"]
[Encoding::InvalidByteSequenceError, "\"\\n\" on ISO-2022-JP"]
[Encoding::InvalidByteSequenceError, "\"\\e(\" followed by \"I\" on ISO-2022-JP"]
[Encoding::InvalidByteSequenceError, "incomplete \"\\e\" on ISO-2022-JP"]
[Encoding::UndefinedConversionError, "\"\\xAF\\xFE\" to UTF-8 in conversion from ISO-2022-JP to stateless-ISO-2022-JP to EUC-JP to UTF-8"]
[Encoding::InvalidByteSequenceError, "\"F\" followed by \"\\x10\" on ISO-2022-JP"]
[Encoding::InvalidByteSequenceError, "incomplete \"F\" on ISO-2022-JP"]
[Encoding::InvalidByteSequenceError, "\"\\x80\" on ISO-2022-JP"]
[Encoding::InvalidByteSequenceError, "incomplete \"\\e(\" on ISO-2022-JP"]
[Encoding::InvalidByteSequenceError, "\"`\" on CP50221"]
[Encoding::InvalidByteSequenceError, "\"\\x80\" on CP51932"]
""
