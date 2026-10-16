def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end

t(:fold) { ["ß" =~ /ss/i, "ss" =~ /ß/i, "ﬀ" =~ /ff/i, "İ" =~ /i/i, "Σ" =~ /ς/i, "K" =~ /k/i] }
t(:props) { ["aΩ漢ア" .scan(/\p{Greek}|\p{Han}|\p{Katakana}/), "a1_" =~ /\p{Word}{3}/, "\u{1F600}" =~ /\p{Emoji}/, "١٢" =~ /\d/, "١٢" =~ /\p{Nd}/, "ǅ" =~ /\p{Lt}/, (Regexp.new('\p{In_Greek}') =~ "α" rescue $!.class), "x" =~ /\p{^L}/] }
t(:grapheme) { "éx🇯🇵".scan(/\X/) }
t(:recursion) { /\A(?<p>\((?:\g<p>|[^()])*\))\z/ =~ "((a)(b))" }
t(:cond) { [/(a)?(?(1)b|c)/.match("ab")[0], /(a)?(?(1)b|c)/.match("c")[0]] }
t(:keep) { "foobar".sub(/foo\Kbar/, "X") }
t(:absent) { "/* a */ b */".match(%r{/\*(?~\*/)\*/})[0] }
t(:backref_level) { /\A(?<a>a|b\g<a>c)\k<a+0>\z/ =~ "bacbac" }
t(:G) { "aab".scan(/\Ga/) }
t(:lookbehind_var) { "abcd" =~ /(?<=ab|abc)d/ }
t(:named_assign) { if /(?<yy>\d+)/ =~ "x12" then yy end }
t(:match_methods) { m = "hello".match(/l+/); [m.byteoffset(0), m.begin(0), m.match(0), m.match_length(0), m.size, m.to_a, "hello".byteindex("l"), "héllo".match(/l/).pre_match.bytesize] }
t(:regex_options) { [/x/mix.options, /a/n.encoding, /a/u.encoding, /\xff/n.source, Regexp.new("a", Regexp::IGNORECASE | Regexp::EXTENDED).inspect, Regexp.new("a", "mi").inspect, /a/.match?("a", 1)] }
t(:regex_enc_err) { /é/ =~ "é".encode("ISO-8859-1") }
t(:regex_bad) { Regexp.new("[a-") }
t(:regex_warn_dup) { Regexp.new("[aa]") }
t(:sjis_regex) { "表".encode("Shift_JIS") =~ Regexp.new("\\\\".encode("Shift_JIS")) }
t(:euc_regex) { "あいう".encode("EUC-JP").scan(Regexp.new(".".encode("EUC-JP"))).size }
t(:utf16_regex) { "ab".encode("UTF-16LE") =~ Regexp.new("b".encode("UTF-16LE")) }
t(:gsub_hash_enc) { "aé".encode("UTF-16BE").gsub("é".encode("UTF-16BE"), "e".encode("UTF-16BE")).encode("UTF-8") }
t(:enc_list) { [Encoding.list.size, Encoding.name_list.size, Encoding.aliases.size, Encoding.find("locale").name, Encoding.find("filesystem").name, Encoding::Converter.search_convpath("ISO-8859-1", "EUC-JP")] }
t(:enc_dummy) { [Encoding::UTF_16.dummy?, Encoding::ISO_2022_JP.dummy?, "a".force_encoding("UTF-7").valid_encoding?, Encoding::UTF_8.ascii_compatible?] }
t(:iso2022) { "日本語".encode("ISO-2022-JP").bytes }
t(:iso2022_back) { "\e$BF|K\\\e(B".force_encoding("ISO-2022-JP").encode("UTF-8") }
t(:cp50221) { "ｱ".encode("CP50221").bytes }
t(:gb18030) { ["€".encode("GB18030").bytes, "\u{10000}".encode("GB18030").bytes] }
t(:big5) { "中文".encode("Big5").bytes }
t(:big5hkscs) { "\u{20AC}".encode("Big5-HKSCS").bytes rescue $!.class }
t(:euctw) { "中".encode("EUC-TW").bytes }
t(:utf7) { "a€".encode("UTF-7") rescue $!.class }
t(:cesu) { "\u{10000}".encode("CESU-8").bytes }
t(:emacs_mule) { "日".encode("Emacs-Mule").bytes rescue $!.class }
t(:windows) { ["€".encode("Windows-1252").bytes, "Ж".encode("Windows-1251").bytes, "Ж".encode("KOI8-R").bytes, "€".encode("IBM437") ] rescue $!.message }
t(:mac) { "é".encode("macRoman").bytes }
t(:ibm) { "é".encode("IBM037").bytes rescue $!.class }
t(:converter) { ec = Encoding::Converter.new("UTF-8", "EUC-JP"); [ec.convert("あ").bytes, ec.finish, ec.source_encoding, ec.replacement] }
t(:converter_err) { ec = Encoding::Converter.new("UTF-8", "ISO-8859-1"); ec.primitive_convert(+"aあb", dst = +"", nil, nil); [ec.primitive_errinfo, ec.last_error&.class, dst] }
t(:converter_newline) { Encoding::Converter.new("UTF-8", "UTF-8", universal_newline: true).convert("a\r\nb\rc") }
t(:str_encode_utf32) { "a\u{1F600}".encode("UTF-32LE").bytes.size }
t(:mbc_case) { ["ÀÉÎ".downcase(:ascii), "ǈ".capitalize, "ß".capitalize, "ŉ".upcase, "i".upcase(:turkic), "I".downcase(:turkic), "ΣΑΣ".downcase, "ᾳ".upcase, "ﬃ".capitalize] }
t(:casefold) { ["ß".downcase(:fold), "ǅ".downcase(:fold), "ẞ".casecmp?("ss")] }
t(:str_sjis_ops) { s = "表示".encode("Shift_JIS"); [s.chars.size, s.reverse.encode("UTF-8"), s.index("示".encode("Shift_JIS")), (s.succ.encode("UTF-8") rescue $!.class), s.center(6, "*").bytesize] }
t(:inspect_enc) { ["あ".encode("EUC-JP").inspect, "\xA4".force_encoding("EUC-JP").inspect, "a".encode("UTF-16LE").inspect, "あ".force_encoding("ASCII-8BIT").inspect] }
t(:sym_enc) { [:"あ".encoding, ("a".encode("UTF-16LE").to_sym rescue $!.class), :a.encoding, "é".b.to_sym.inspect] }
t(:unicode_ver) { [RbConfig::CONFIG["UNICODE_VERSION"], RbConfig::CONFIG["UNICODE_EMOJI_VERSION"]] }
