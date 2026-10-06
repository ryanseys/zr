# The ISO-2022-JP family and EUC-JP/Shift_JIS convert as ruby's own
# transcoders do: CP5022x reads SO, SI and eight-bit katakana that
# ISO-2022-JP refuses, a multibyte encoding writes its stateful form
# directly, EUC-JP and Shift_JIS meet by JIS arithmetic, and a
# replacement is the final target's.
def t(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end
["\x1b(A", "\x1b$(A", "\x1b$C", "\x0e", "\x80"].each { |s| t(:invalid_in) { s.force_encoding("iso-2022-jp").encode("utf-8").b } }
%w[UTF-16LE UTF-32BE].each { |d| t(:xml) { "<\">".encode("UTF-8").encode(d, xml: :attr).encode("UTF-8") } }
t(:xml_text) { "<>".encode("UTF-16LE").encode("UTF-16LE", xml: :text).encode("UTF-8") }
t(:cp50221_1) { "\xB1".encode("utf-8", "cp50221") }
t(:cp50221_2) { "\e(I\xB1".encode("utf-8", "cp50221") }
t(:cp50221_3) { "\x0E\xB1".encode("utf-8", "cp50221") }
t(:cp50221_4) { "\e$B\x2D\x21".encode("utf-8", "cp50221") }
t(:cp50220) { "\e(I!_\e(B".encode("sjis", "cp50220").b }
t(:to_cp50220) { "\xA1\xDF".encode("cp50220", "sjis").b }
t(:to_cp50220_2) { "\x8E\xA1\x8E\xFE".encode("cp50220", "cp51932").b }
t(:sjis_unassigned) { "\xEF\x40".encode("EUC-JP", "Shift_JIS").b }
t(:inv_replace) { "\xA1\xA1\xFF".encode("ISO-2022-JP", "EUC-JP", invalid: :replace).b }
t(:inv_replace2) { "\xA4\xA2\xFF\xA4\xA4".encode("ISO-2022-JP", "EUC-JP", invalid: :replace).b }
t(:eucjp_invalid) { "\xA4\xA2\xFF".encode("ISO-2022-JP", "EUC-JP").b }
t(:eucjp_replace_str) { "\xA4\xA2\xFF".encode("ISO-2022-JP", "EUC-JP", invalid: :replace, replace: "*").b }
t(:eucjp_plain) { "a\xA4\xA2b".encode("ISO-2022-JP", "EUC-JP").b }
t(:eucjp_kana) { "\x8E\xB1".encode("ISO-2022-JP", "EUC-JP").b }
t(:cp51932_50221) { "\x8E\xB1\xA4\xA2".encode("CP50221", "CP51932").b }
t(:cp51932_50220) { "\x8E\xB6\x8E\xDE\xA4\xA2".encode("CP50220", "CP51932").b }
t(:so_si) { "\x0E\x31\x0Fa".encode("utf-8", "cp50221") }
t(:si_iso) { "a\x0F".force_encoding("iso-2022-jp").encode("utf-8") }
t(:kana_8bit_bad) { "\xE0".encode("utf-8", "cp50221") }
t(:e2s) { "a\xA4\xA2\x8E\xB1\xfd\xa1\xfe\xfe".encode("Shift_JIS", "EUC-JP").b }
t(:s2e) { "a\x82\xa0\xb1\xef\x40\xef\xfc".encode("EUC-JP", "Shift_JIS").b }
t(:e_undef) { "\x8e\xe0".encode("Shift_JIS", "EUC-JP") }
t(:e_undef3) { "\x8f\xa1\xa1".encode("Shift_JIS", "EUC-JP") }
t(:s_undef) { "\xf0\x40".encode("EUC-JP", "Shift_JIS") }
t(:e_inv) { "\xff".encode("Shift_JIS", "EUC-JP") }
t(:e_inc) { "\xa4".encode("Shift_JIS", "EUC-JP") }
t(:e_follow) { "\xa4a".encode("Shift_JIS", "EUC-JP") }
t(:s_inv) { "\x80".encode("EUC-JP", "Shift_JIS") }
t(:s_inc) { "\x82".encode("EUC-JP", "Shift_JIS") }
t(:s_follow) { "\x82\x20".encode("EUC-JP", "Shift_JIS") }
t(:repl) { "\x8e\xe0\xff\xa4\xa2".encode("Shift_JIS", "EUC-JP", undef: :replace, invalid: :replace).b }
t(:repl_s) { "\xf0\x40\x80\x82\xa0".encode("EUC-JP", "Shift_JIS", undef: :replace, invalid: :replace, replace: "*").b }
t(:convpath) { Encoding::Converter.new("EUC-JP", "Shift_JIS").convpath }
t(:xml) { "<\xA4\xA2>".encode("Shift_JIS", "EUC-JP", xml: :attr).b }
t(:nl) { "a\nb".encode("Shift_JIS", "EUC-JP", newline: :crlf).b }

# xml: escapes between every pair of Unicode encodings.
encodings = %w[UTF-8 UTF-16LE UTF-16BE UTF-32LE UTF-32BE]
encodings.each do |s|
  encodings.each do |d|
    a = "<>".encode(s).encode(d, xml: :text).encode("UTF-8")
    b = '<">'.encode(s).encode(d, xml: :attr).encode("UTF-8")
    c = "<>".encode(s).force_encoding("UTF-8").encode(d, s, xml: :text).encode("UTF-8")
    e = '<">'.encode(s).force_encoding("UTF-8").encode(d, s, xml: :attr).encode("UTF-8")
    p [s, d, a, b, c, e]
  end
end
