# Onigmo's own answers at the edges a port gets wrong: grapheme clusters,
# multi-character case folds, property aliases, ASCII-range options in
# classes, recursion with a level, absent groups, look-behind alternation
# lengths, a backward search over multibyte text, \G under StringScanner,
# and a line anchor at the end of text.
require "strscan"

p "🇯🇵🇺🇸👨‍👩‍👧e\u0301\r\n".scan(/\X/)
p "e\u0301x".match(/\A\X/)[0].bytes
p ["ss" =~ /ß/i, "ß" =~ /ss/i, "ﬁ" =~ /fi/i, "FI" =~ /ﬁ/i, "İ" =~ /i̇/i]
p ["Ab" =~ /\p{Lu}\p{Ll}/, "a" =~ /\p{L}/, "日" =~ /\p{Han}/, "日" =~ /\p{In_CJK_Unified_Ideographs}/, "a" =~ /\p{^Alpha}/]
p ["é" =~ /(?a)\w/, "é" =~ /(?u)\w/, "é" =~ /(?a)[\w]/, "é" =~ /[[:alpha:]]/, "é" =~ /(?a)[[:alpha:]]/, "é" =~ /(?a:\b)é/]
p "((a))".match(/\A(?<p>\((?<i>\g<p>|a)\))\z/)&.captures
p "abba".match(/\A(?<a>.)(?<b>.)\k<b>\k<a>\z/)&.named_captures
p "xyyx".match(/\A(?<r>|.\g<r>\k<r+0>)\z/)&.[](0)
p "/* a */ b */".match(%r{/\*(?~\*/)\*/})[0]
p ["xab".match(/(?<=a|xa)b/)&.begin(0), "ab" =~ /(?<!c|dd)b/]
p "日本語日本".rindex(/日/), "日本語日本".rindex(/本/, 3)
s = StringScanner.new("aab")
p [s.scan(/\Ga/), s.scan(/\Ga/), s.scan(/\Gb/), s.pos]
p ["ab\ncd\n".rindex(/$/), "ab\n" =~ /\n$/, "\n" =~ /^$/, "ab\n".scan(/$/).size]
p "a\nb".match(/a$\n^b/m)&.[](0)
p ("(" * 100 + "a" + ")" * 100).then { |pat| Regexp.new(pat).match("a").size }
p "aaa".match(/(a)(?:\1|b)*/)[0]

