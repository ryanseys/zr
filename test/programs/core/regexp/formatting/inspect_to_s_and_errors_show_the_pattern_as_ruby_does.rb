# Regexp#inspect, #to_s and a RegexpError's message show the pattern as
# rb_reg_expr_str writes it: a bare `/` escaped, a control byte as \xHH,
# a character past ASCII as \uXXXX when the reader's encoding is not the
# pattern's, and to_s folds a whole `(?opts:...)` group into its options.

p Regexp.new("a/b\t\x01").inspect
p Regexp.new("日本/").inspect
p Regexp.new("\\/").inspect
p Regexp.new("\xff/".b).inspect
p Regexp.new("é", Regexp::IGNORECASE | Regexp::EXTENDED).inspect
p /a/n.inspect

p Regexp.new("(?i:ab)").to_s
p Regexp.new("(?i-mx:ab)").to_s
p Regexp.new("(?m)a").to_s
p Regexp.new("(?i:a)b").to_s
p Regexp.new("(?x)(?i:a").then { :unreachable } rescue p $!.message
p Regexp.new("a/\n").to_s
p Regexp.new("é/").to_s.encoding

["(日", "(é/\x01", "[b-a]", "(?<a\0b>x)", "\\k<nope>", "\\u{110000}", "\\xe3\\x81"].each do |pattern|
  Regexp.new(pattern)
rescue RegexpError => e
  p [e.message, e.message.encoding]
end

[["(\xff".b, 0], ["(\xe9".dup.force_encoding("ISO-8859-1"), 0], ["(", Regexp::MULTILINE | Regexp::IGNORECASE | Regexp::EXTENDED]].each do |pattern, options|
  Regexp.new(pattern, options)
rescue RegexpError => e
  p [e.message.b, e.message.encoding]
end

