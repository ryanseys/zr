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

