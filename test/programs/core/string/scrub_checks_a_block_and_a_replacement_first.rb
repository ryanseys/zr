# String#scrub refuses a block and a replacement together, also for
# valid text, and stops when the block changes the String.
def t
  p yield
rescue => e
  p [e.class, e.message]
end
t { "a".scrub("?") { |c| c } }
t { "�あ".encode("UTF-16BE").scrub("") {} }
t { "a\x81c".scrub { |c| "<#{c.unpack1("H*")}>" } }
t { "a\x81".scrub { |c| c } }
str = ("abcあ".b << "\xE3\x80".b).force_encoding("UTF-8")
t { str.scrub { |_| str << "1234567890"; "?" } }
t { "\x00\xD8\x42\x30".force_encoding(Encoding::UTF_16LE).scrub { |b| p b; "?".encode(Encoding::UTF_16LE) }.encode("UTF-8") }
