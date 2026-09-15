# UTF8-MAC and the carriers' UTF-8 walk as UTF-8 walks: a character is
# its code point, which inspect shows, and CESU-8, which is not among
# them, shows its own the same way.
%w[UTF8-MAC UTF8-DoCoMo UTF8-KDDI UTF8-SoftBank CESU-8].each do |name|
  s = "aé\u{E6A0}ÿ".b.force_encoding(name)
  p [name, s.length, s.chars.size, s.ord, s[1].ord, s.valid_encoding?, s.reverse.b, s.upcase.b, s.codepoints.size]
  p s, s[1], 0xE9.chr(name).b, s.dump, s.unpack("U*").size
  p s.center(8, "*").b, s =~ /é/u rescue p $!
  p "%s!" % s rescue p $!
  p s.scrub.b, s.inspect.encoding, s.each_grapheme_cluster.count
end

__END__
["UTF8-MAC", 4, 4, 97, 233, true, "\xC3\xBF\xEE\x9A\xA0\xC3\xA9a", "A\xC3\x89\xEE\x9A\xA0\xC5\xB8", 4]
"a\u00E9\uE6A0\u00FF"
"\u00E9"
"\xC3\xA9"
"\"a\\xC3\\xA9\\xEE\\x9A\\xA0\\xC3\\xBF\""
4
#<Encoding::CompatibilityError: incompatible encoding regexp match (UTF-8 regexp with UTF8-MAC string)>
"a\u00E9\uE6A0\u00FF!"
"a\xC3\xA9\xEE\x9A\xA0\xC3\xBF"
#<Encoding:UTF-8>
4
["UTF8-DoCoMo", 4, 4, 97, 233, true, "\xC3\xBF\xEE\x9A\xA0\xC3\xA9a", "A\xC3\x89\xEE\x9A\xA0\xC5\xB8", 4]
"a\u00E9\uE6A0\u00FF"
"\u00E9"
"\xC3\xA9"
"\"a\\xC3\\xA9\\xEE\\x9A\\xA0\\xC3\\xBF\""
4
#<Encoding::CompatibilityError: incompatible encoding regexp match (UTF-8 regexp with UTF8-DoCoMo string)>
"a\u00E9\uE6A0\u00FF!"
"a\xC3\xA9\xEE\x9A\xA0\xC3\xBF"
#<Encoding:UTF-8>
4
["UTF8-KDDI", 4, 4, 97, 233, true, "\xC3\xBF\xEE\x9A\xA0\xC3\xA9a", "A\xC3\x89\xEE\x9A\xA0\xC5\xB8", 4]
"a\u00E9\uE6A0\u00FF"
"\u00E9"
"\xC3\xA9"
"\"a\\xC3\\xA9\\xEE\\x9A\\xA0\\xC3\\xBF\""
4
#<Encoding::CompatibilityError: incompatible encoding regexp match (UTF-8 regexp with UTF8-KDDI string)>
"a\u00E9\uE6A0\u00FF!"
"a\xC3\xA9\xEE\x9A\xA0\xC3\xBF"
#<Encoding:UTF-8>
4
["UTF8-SoftBank", 4, 4, 97, 233, true, "\xC3\xBF\xEE\x9A\xA0\xC3\xA9a", "A\xC3\x89\xEE\x9A\xA0\xC5\xB8", 4]
"a\u00E9\uE6A0\u00FF"
"\u00E9"
"\xC3\xA9"
"\"a\\xC3\\xA9\\xEE\\x9A\\xA0\\xC3\\xBF\""
4
#<Encoding::CompatibilityError: incompatible encoding regexp match (UTF-8 regexp with UTF8-SoftBank string)>
"a\u00E9\uE6A0\u00FF!"
"a\xC3\xA9\xEE\x9A\xA0\xC3\xBF"
#<Encoding:UTF-8>
4
["CESU-8", 4, 4, 97, 233, true, "\xC3\xBF\xEE\x9A\xA0\xC3\xA9a", "A\xC3\x89\xEE\x9A\xA0\xC5\xB8", 4]
"a\u00E9\uE6A0\u00FF"
"\u00E9"
"\xC3\xA9"
"\"a\\xC3\\xA9\\xEE\\x9A\\xA0\\xC3\\xBF\""
4
#<Encoding::CompatibilityError: incompatible encoding regexp match (UTF-8 regexp with CESU-8 string)>
"a\u00E9\uE6A0\u00FF!"
"a\xC3\xA9\xEE\x9A\xA0\xC3\xBF"
#<Encoding:UTF-8>
4
