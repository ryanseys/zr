# sub and gsub read a replacement's backslashes as CRuby's rb_reg_regsub
# reads them: a character at a time in the replacement's own encoding,
# so UTF-16 and UTF-32 replacements fill in their groups and a
# Shift_JIS trail byte 0x5C is no backslash. What the pieces join into
# follows the encodings of the text, the replacement and the groups.
def show(label)
  value = yield
  p [label, value.encoding.name, value.b]
rescue StandardError => e
  p [label, e.class, e.message]
end

show(:named_ref) { "ab".sub(/(?<x>a)/, "[\\k<x>]") }
show(:unknown_name) { "ab".sub(/(?<x>a)/, "[\\k<y>]") }
show(:open_name) { "ab".sub(/(?<x>a)/, "[\\k<x]") }
show(:bare_k) { "ab".sub(/(a)/, "[\\k]") }
show(:k_then_x) { "ab".sub(/(a)/, "[\\kx]") }
show(:trailing) { "ab".sub(/a/, "x\\") }
show(:double) { "ab".sub(/a/, "x\\\\y") }
show(:past_groups) { "ab".sub(/(a)/, "[\\9]") }
show(:plus_none) { "ab".sub(/a/, "[\\+]") }
show(:plus_last) { "abc".sub(/(a)(x)?(b)?/, "[\\+]") }
show(:numbered_under_names) { "ab".sub(/(?<x>a)(b)/, "[\\1|\\2]") }
show(:string_pattern) { "ab".sub("a", "[\\0|\\1|\\&|\\`|\\']") }
show(:string_pattern_name) { "ab".sub("a", "[\\k<a>]") }
show(:duplicate_names) { "xy".gsub(/(?<a>x)|(?<a>y)/, "<\\k<a>>") }
show(:other_escape) { "ab".sub(/a/, "\\q\\n") }
show(:escaped_multibyte) { "ab".sub(/a/, "\\é") }
show(:name_multibyte) { "ab".sub(/(?<é>a)/, "\\k<é>") }

sjis = ->(s) { s.encode("Shift_JIS") }
show(:sjis_trail) { sjis.("表a").sub(sjis.("a"), sjis.("表0")) }
show(:sjis_group) { sjis.("表a").sub(Regexp.new(sjis.("(表)")), sjis.("\\1\\1")) }
show(:sjis_gsub) { sjis.("ソ表ソ").gsub(Regexp.new(sjis.("ソ")), sjis.("表\\0")) }

%w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE].each do |enc|
  u = ->(s) { s.encode(enc) }
  text = u.("héllo wörld")
  show(:"#{enc}_groups") { text.sub(Regexp.new(u.("(h)(é)")), u.("<\\2\\1\\0>")) }
  show(:"#{enc}_named") { text.gsub(Regexp.new(u.("(?<v>[éö])")), u.("[\\k<v>]")) }
  show(:"#{enc}_pre_post") { text.sub(Regexp.new(u.(" ")), u.("|\\'|\\`|")) }
  show(:"#{enc}_backslashes") { text.sub(Regexp.new(u.("o")), u.("\\\\\\x\\")) }
  show(:"#{enc}_plain") { text.gsub(Regexp.new(u.("l")), u.("L")) }
  show(:"#{enc}_bad_name") { text.sub(Regexp.new(u.("(?<v>h)")), u.("\\k<w>")) }
  show(:"#{enc}_open_name") { text.sub(Regexp.new(u.("(?<v>h)")), u.("\\k<v")) }
end

show(:utf16_into_utf8) { "abc".gsub("b", "x".encode("UTF-16LE")) }
show(:utf16_into_utf8_sub_at_start) { "bc".sub("b", "x".encode("UTF-16LE")) }
show(:utf16_into_utf8_sub_mid) { "abc".sub("b", "x".encode("UTF-16LE")) }
show(:euc_into_ascii_utf8) { "abc".sub("b", "字".encode("EUC-JP")) }
show(:euc_into_utf8) { "aéc".sub("c", "字".encode("EUC-JP")) }
show(:euc_into_utf8_gsub) { "aéc".gsub("c", "字".encode("EUC-JP")) }
show(:utf8_into_binary) { "a\xFFc".b.sub("c", "é") }
show(:utf8_into_binary_gsub) { "abc".b.gsub("b", "é") }
show(:group_of_binary) { "a\xFFc".b.sub(/(\xFF)/n, "é\\1") }
show(:ascii_repl_utf16) { "héllo".encode("UTF-16LE").sub(Regexp.new("l".encode("UTF-16LE")), "L") }
show(:block_utf16) { "abc".encode("UTF-32BE").gsub(Regexp.new("b".encode("UTF-32BE"))) { |m| m + m } }
show(:hash_euc) { "abc".gsub(/b/, "b" => "字".encode("EUC-JP")) }
show(:sub_bang) { s = +"hello".encode("UTF-16BE"); s.sub!(Regexp.new("(l+)".encode("UTF-16BE")), "<\\1>".encode("UTF-16BE")); s }
show(:gsub_bang) { s = +"hello".encode("UTF-32LE"); s.gsub!(Regexp.new("l".encode("UTF-32LE")), "\\0\\0".encode("UTF-32LE")); s }

__END__
[:named_ref, "UTF-8", "[a]b"]
[:unknown_name, IndexError, "undefined group name reference: y"]
[:open_name, RuntimeError, "invalid group name reference format"]
[:bare_k, "UTF-8", "[\\k]b"]
[:k_then_x, "UTF-8", "[\\kx]b"]
[:trailing, "UTF-8", "x\\b"]
[:double, "UTF-8", "x\\yb"]
[:past_groups, "UTF-8", "[]b"]
[:plus_none, "UTF-8", "[]b"]
[:plus_last, "UTF-8", "[b]c"]
[:numbered_under_names, "UTF-8", "[|]"]
[:string_pattern, "UTF-8", "[a||a||b]b"]
[:string_pattern_name, IndexError, "undefined group name reference: a"]
[:duplicate_names, "UTF-8", "<x><y>"]
[:other_escape, "UTF-8", "\\q\\nb"]
[:escaped_multibyte, "UTF-8", "\\\xC3\xA9b"]
[:name_multibyte, "UTF-8", "ab"]
[:sjis_trail, "Shift_JIS", "\x95\\\x95\\0"]
[:sjis_group, "Shift_JIS", "\x95\\\x95\\a"]
[:sjis_gsub, "Shift_JIS", "\x95\\\x83\\\x95\\\x95\\\x83\\"]
[:"UTF-16LE_groups", "UTF-16LE", "<\x00\xE9\x00h\x00h\x00\xE9\x00>\x00l\x00l\x00o\x00 \x00w\x00\xF6\x00r\x00l\x00d\x00"]
[:"UTF-16LE_named", "UTF-16LE", "h\x00[\x00\xE9\x00]\x00l\x00l\x00o\x00 \x00w\x00[\x00\xF6\x00]\x00r\x00l\x00d\x00"]
[:"UTF-16LE_pre_post", "UTF-16LE", "h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d\x00|\x00h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d\x00"]
[:"UTF-16LE_backslashes", "UTF-16LE", "h\x00\xE9\x00l\x00l\x00\\\x00\\\x00x\x00\\\x00 \x00w\x00\xF6\x00r\x00l\x00d\x00"]
[:"UTF-16LE_plain", "UTF-16LE", "h\x00\xE9\x00L\x00L\x00o\x00 \x00w\x00\xF6\x00r\x00L\x00d\x00"]
[:"UTF-16LE_bad_name", IndexError, "undefined group name reference: w"]
[:"UTF-16LE_open_name", RuntimeError, "invalid group name reference format"]
[:"UTF-16BE_groups", "UTF-16BE", "\x00<\x00\xE9\x00h\x00h\x00\xE9\x00>\x00l\x00l\x00o\x00 \x00w\x00\xF6\x00r\x00l\x00d"]
[:"UTF-16BE_named", "UTF-16BE", "\x00h\x00[\x00\xE9\x00]\x00l\x00l\x00o\x00 \x00w\x00[\x00\xF6\x00]\x00r\x00l\x00d"]
[:"UTF-16BE_pre_post", "UTF-16BE", "\x00h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d\x00|\x00h\x00\xE9\x00l\x00l\x00o\x00|\x00w\x00\xF6\x00r\x00l\x00d"]
[:"UTF-16BE_backslashes", "UTF-16BE", "\x00h\x00\xE9\x00l\x00l\x00\\\x00\\\x00x\x00\\\x00 \x00w\x00\xF6\x00r\x00l\x00d"]
[:"UTF-16BE_plain", "UTF-16BE", "\x00h\x00\xE9\x00L\x00L\x00o\x00 \x00w\x00\xF6\x00r\x00L\x00d"]
[:"UTF-16BE_bad_name", IndexError, "undefined group name reference: w"]
[:"UTF-16BE_open_name", RuntimeError, "invalid group name reference format"]
[:"UTF-32LE_groups", "UTF-32LE", "<\x00\x00\x00\xE9\x00\x00\x00h\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00>\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
[:"UTF-32LE_named", "UTF-32LE", "h\x00\x00\x00[\x00\x00\x00\xE9\x00\x00\x00]\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00[\x00\x00\x00\xF6\x00\x00\x00]\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
[:"UTF-32LE_pre_post", "UTF-32LE", "h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00|\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
[:"UTF-32LE_backslashes", "UTF-32LE", "h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00\\\x00\x00\x00\\\x00\x00\x00x\x00\x00\x00\\\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00"]
[:"UTF-32LE_plain", "UTF-32LE", "h\x00\x00\x00\xE9\x00\x00\x00L\x00\x00\x00L\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00L\x00\x00\x00d\x00\x00\x00"]
[:"UTF-32LE_bad_name", IndexError, "undefined group name reference: w"]
[:"UTF-32LE_open_name", RuntimeError, "invalid group name reference format"]
[:"UTF-32BE_groups", "UTF-32BE", "\x00\x00\x00<\x00\x00\x00\xE9\x00\x00\x00h\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00>\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
[:"UTF-32BE_named", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00[\x00\x00\x00\xE9\x00\x00\x00]\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00[\x00\x00\x00\xF6\x00\x00\x00]\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
[:"UTF-32BE_pre_post", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d\x00\x00\x00|\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00|\x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
[:"UTF-32BE_backslashes", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00l\x00\x00\x00l\x00\x00\x00\\\x00\x00\x00\\\x00\x00\x00x\x00\x00\x00\\\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00l\x00\x00\x00d"]
[:"UTF-32BE_plain", "UTF-32BE", "\x00\x00\x00h\x00\x00\x00\xE9\x00\x00\x00L\x00\x00\x00L\x00\x00\x00o\x00\x00\x00 \x00\x00\x00w\x00\x00\x00\xF6\x00\x00\x00r\x00\x00\x00L\x00\x00\x00d"]
[:"UTF-32BE_bad_name", IndexError, "undefined group name reference: w"]
[:"UTF-32BE_open_name", RuntimeError, "invalid group name reference format"]
[:utf16_into_utf8, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and UTF-16LE"]
[:utf16_into_utf8_sub_at_start, "UTF-16LE", "x\x00c"]
[:utf16_into_utf8_sub_mid, "UTF-16LE", "ax\x00c"]
[:euc_into_ascii_utf8, "EUC-JP", "a\xBB\xFAc"]
[:euc_into_utf8, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and EUC-JP"]
[:euc_into_utf8_gsub, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and EUC-JP"]
[:utf8_into_binary, Encoding::CompatibilityError, "incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8"]
[:utf8_into_binary_gsub, "UTF-8", "a\xC3\xA9c"]
[:group_of_binary, Encoding::CompatibilityError, "incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)"]
[:ascii_repl_utf16, Encoding::CompatibilityError, "incompatible character encodings: UTF-16LE and UTF-8"]
[:block_utf16, "UTF-32BE", "\x00\x00\x00a\x00\x00\x00b\x00\x00\x00b\x00\x00\x00c"]
[:hash_euc, "EUC-JP", "a\xBB\xFAc"]
[:sub_bang, "UTF-16BE", "\x00h\x00e\x00<\x00l\x00l\x00>\x00o"]
[:gsub_bang, "UTF-32LE", "h\x00\x00\x00e\x00\x00\x00l\x00\x00\x00l\x00\x00\x00l\x00\x00\x00l\x00\x00\x00o\x00\x00\x00"]
