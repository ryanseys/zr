def t(l)
  r = yield
  puts "#{l}: #{r.inspect}"
rescue Exception => e
  puts "#{l}: !#{e.class}: #{e.message[0, 200]}"
end
t(:enc) { s = "héllo"; [s.bytesize, s.encode("UTF-16LE").bytes.first(4), s.encode("ISO-8859-1").bytes, s.force_encoding("BINARY").valid_encoding?, "\xff".scrub("?"), "abc".encode("UTF-32BE").size] }
t(:enc2) { ["日本".encode("Shift_JIS").bytes, "日本".encode("EUC-JP").inspect, "\u00e9".unicode_normalize(:nfd).bytes, "Ǆ".downcase, "ß".upcase, "İ".downcase.bytes, "ﬀ".upcase, "ǅ".swapcase] }
t(:enc_err) { "\xff".encode("UTF-16") }
t(:enc_undef) { "é".encode("US-ASCII") }
t(:enc_opts) { ["é\n".encode("US-ASCII", undef: :replace, replace: "*", crlf_newline: true), "<é>".encode("US-ASCII", xml: :text), "é".encode("US-ASCII", fallback: {"é" => "e"})] }
t(:compat) { ("a".force_encoding("ASCII-8BIT") + "é") }
t(:compat2) { ("\xff".b + "é") }
t(:inspect) { ["\e\x00\u200b\u{1F600}", "\xff\xfe".b, "a\"b\\", "#{1}\#{x}", "é".encode("UTF-16LE"), "\x80".force_encoding("Shift_JIS")].map(&:inspect) }
t(:dump) { ["é\n\x01".dump, "\"\\u00e9\"".undump] }
t(:fmt_str) { ["abc".center(9, "*"), "x".ljust(4, "ab"), "%-10s|" % "日本", "abc".succ, "az".succ, "zz99".succ, "a9".succ, "Zz".succ, "".succ] }
t(:split) { ["a,b,,c,,".split(","), "a,b,,c,,".split(",", -1), " a  b ".split, "abc".split(""), "a1b2".split(/(\d)/), "aXbXc".split("X", 2), "abc".split(/b/) { }] }
t(:scan) { ["a1b22c333".scan(/\d+/), "abab".scan(/(a)(b)/), "hello world".gsub(/o/) { $~.begin(0).to_s }, "abc".gsub(/b/, "b" => "B"), "aaa".sub(/a/, '\0\0'), "x-y".gsub(/(?<l>\w)/, '<\k<l>>')] }
t(:regex) { m = /(?<y>\d{4})-(?<m>\d\d)/.match("on 2024-05!"); [m.pre_match, m.post_match, m.named_captures, m.offset(:m), m.values_at(1, 2), m.deconstruct_keys([:y]), $~ && $1] }
t(:regex2) { [/a.c/m =~ "a\nc", /(?i)abc/ =~ "ABC", /\p{Han}+/.match("漢字abc")[0], /x*+x/ =~ "xxx", /(?<!a)b/ =~ "ab cb", "aaa" =~ /a{,2}/, /\Rx/ =~ "\r\nx", /(?~abc)/.match("xabcx")[0]] }
t(:regex_timeout) { Regexp.timeout }
t(:regex_timeout2) { Regexp.new("(a+)+$", timeout: 0.01).match?("a" * 50 + "b") }
t(:regex_linear) { [Regexp.linear_time?(/a+/), Regexp.linear_time?(/(a)\1/)] }
t(:regex_union) { [Regexp.union("a.b", /c/i), Regexp.escape("a*b?"), /a/.source, /a#{1}b/o.to_s, (Regexp.new("(") rescue $!.message)] }
t(:sym) { [:a <=> :b, :abc.size, :"foo bar".inspect, %s{x}, (:a.to_proc.call("x") rescue $!.class), :"é".inspect, :"9a".inspect, :[]=.inspect, :"@@a".inspect, :"$1".inspect, :"a=".inspect, :"!".inspect] }
t(:str_misc) { ["Hello World".swapcase, "hello"[1..], "hello"[-3, 2], "hello".byteslice(1, 2), "a%b" % [], "abc".unpack1("H*"), ["616263"].pack("H*"), "hello".delete("l"), "aaabbb".squeeze, "hello".count("lo"), "hello".tr("el", "ip"), "hello".tr("a-y", "b-z"), "abc".each_char.to_a, "ab\ncd".lines, "abc".start_with?(/a./), "title case".capitalize, "  x  ".strip, "x\u3000".strip] }
t(:str_unicode) { ["éa".each_grapheme_cluster.to_a, "🇯🇵🇺🇸".grapheme_clusters, "ä".unicode_normalize(:nfkc), "Ａ".unicode_normalize(:nfkc), "e\u0301".unicode_normalized?] }
t(:heredoc) { <<~X }
    a
      b
    c
  X
t(:str_cmp) { ["a".casecmp("A"), "é".casecmp?("É"), "abc" <=> "abd", "a" == :a, "a".eql?("a"), "abc".hash == "abc".hash] }
t(:sprintf_enc) { format("%s", "é".encode("UTF-16LE")) }
t(:str_mult) { ["ab" * 3, ("ab" * -1 rescue $!.message), "a".ord, 233.chr, 233.chr(Encoding::UTF_8), (256.chr rescue $!.message), 0x1F600.chr("UTF-8")] }
t(:crypt) { "pw".crypt("ab") }
t(:sum) { ["abc".sum, "abc".sum(8), ("abc".crypt("$1$salt") rescue $!.class)] }
