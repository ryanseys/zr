# GB18030's four-byte characters count through Unicode in order, CESU-8
# writes a character past the BMP as two surrogates of three bytes each,
# and IBM037 holds ISO-8859-1's bytes in EBCDIC order. UTF-7 and
# ISO-2022-JP-2 have no converter in ruby at all.
p "ñ€\u{1F600}".encode("GB18030").b, "\x81\x30\x8A\x39\x95\x32\x82\x36".force_encoding("GB18030").encode("UTF-8")
p "\x84\x31\xA4\x39".force_encoding("GB18030").encode("UTF-8"), "\x90\x30\x81\x30".force_encoding("GB18030").encode("UTF-8").ord.to_s(16)
["\x84\x31\xA5\x30", "\xE3\x32\x9A\x36", "\x81\x30", "\x81\x30\x81", "\x81\x30x0"].each do |bad|
  begin
    p bad.dup.force_encoding("GB18030").encode("UTF-8")
  rescue => e
    p [e.class, e.message]
  end
end
p "\xE3\x32\x9A\x36".force_encoding("GB18030").encode("UTF-8", undef: :replace)
p "\u{1F600}".encode("CESU-8").b, "日".encode("CESU-8").b, "\xED\xA0\xBD\xED\xB8\x80".force_encoding("CESU-8").encode("UTF-8")
["\xED\xA0\xBD", "\xED\xB8\x80", "\xE6\x97", "\xF0\x9F\x98\x80", "\xED\xA0\xBDx"].each do |bad|
  begin
    p bad.dup.force_encoding("CESU-8").encode("UTF-8")
  rescue => e
    p [e.class, e.message]
  end
end
p "éaZ".encode("IBM037").b, ("日".encode("IBM037") rescue $!.message), "\xC1\x81".force_encoding("IBM037").encode("UTF-8")
p (0..255).map(&:chr).join.force_encoding("IBM037").encode("UTF-8").bytesize
p ("a".encode("UTF-7") rescue $!), ("a".encode("ISO-2022-JP-2") rescue $!)

__END__
"\x810\x8A9\xA2\xE3\x949\xFC6"
"ñ𠀀"
"\uFFFF"
"10000"
[Encoding::UndefinedConversionError, "\"\\x841\\xA50\" from GB18030 to UTF-8"]
[Encoding::UndefinedConversionError, "\"\\xE32\\x9A6\" from GB18030 to UTF-8"]
[Encoding::InvalidByteSequenceError, "incomplete \"\\x810\" on GB18030"]
[Encoding::InvalidByteSequenceError, "incomplete \"\\x810\\x81\" on GB18030"]
[Encoding::InvalidByteSequenceError, "\"\\x810\" followed by \"x\" on GB18030"]
"�"
"\xED\xA0\xBD\xED\xB8\x80"
"\xE6\x97\xA5"
"😀"
[Encoding::InvalidByteSequenceError, "incomplete \"\\xED\\xA0\\xBD\" on CESU-8"]
[Encoding::InvalidByteSequenceError, "\"\\xED\" followed by \"\\xB8\" on CESU-8"]
[Encoding::InvalidByteSequenceError, "incomplete \"\\xE6\\x97\" on CESU-8"]
[Encoding::InvalidByteSequenceError, "\"\\xF0\" on CESU-8"]
[Encoding::InvalidByteSequenceError, "\"\\xED\\xA0\\xBD\" followed by \"x\" on CESU-8"]
"Q\x81\xE9"
"U+65E5 to ISO-8859-1 in conversion from UTF-8 to ISO-8859-1 to IBM037"
"Aa"
384
#<Encoding::ConverterNotFoundError: code converter not found (UTF-8 to UTF-7)>
#<Encoding::ConverterNotFoundError: code converter not found (UTF-8 to ISO-2022-JP-2)>
