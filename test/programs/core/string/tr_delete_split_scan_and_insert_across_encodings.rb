# tr, tr_s, delete, split, scan, insert and succ over Strings in four
# encodings, valid and broken, give ruby's results and errors in ruby's
# order: tr_trans checks nothing for an empty receiver and reads `to`
# only while `from` has characters, a range skips codes that are no
# character, split checks a String pattern before the receiver and walks
# by character heads, scan refuses a broken receiver, and insert checks
# the encodings before the index.
def e(s) = s.dup.force_encoding(Encoding::EUC_JP)
def s(str) = str.dup.force_encoding(Encoding::SJIS)
def u(str) = str.dup.force_encoding(Encoding::UTF_8)
STRINGS = ["".b, "a".b, "\x80".b, e(""), e("a"), e("\xa1\xa1"), e("\x8f\xa1\xa1"), e("\xa1"), s("\x81\x40"), s("\x81a"), s("\x81"), u("\xc2\x80"), u("\xc2")]
def show(x) = x.is_a?(String) ? [x.encoding.name, x.b] : x
def r(name, *args)
  out = begin
    yield
  rescue => ex
    [ex.class, ex.message.b[0, 50]]
  end
  puts "#{name} #{args.map { |a| show(a).inspect }.join(" ")} => #{show(out).inspect}"
end
STRINGS.each do |s1|
  STRINGS.each do |s2|
    r(:delete, s1, s2) { s1.delete(s2) }
    r(:split, s1, s2) { s1.split(s2) }
    r(:scan, s1, s2) { s1.scan(s2) }
    r(:insert, s1, 2, s2) { s1.dup.insert(2, s2) }
  end
end
STRINGS.first(7).each do |s1|
  STRINGS.each { |s2| STRINGS.each { |s3| r(:tr, s1, s2, s3) { s1.tr(s2, s3) }; r(:tr_s, s1, s2, s3) { s1.tr_s(s2, s3) } } }
end
r(:succ) { "\x7f".dup.force_encoding(Encoding::US_ASCII).succ }
r(:succ) { "\xff".b.succ }
r(:tr_range) { s("\x84M\x84N\x84O\x84P\x84Q").tr(s("\x84@-\x84`"), s("\x84p-\x84\x91")) }
r(:tr_range) { s("\xCF\xD0\xD1\xD2\xD3").tr(s("\xCF-\xD3"), s("\x83}-\x83\x82")) }
r(:tr_bang) { "".freeze.tr!("a", "b") }
r(:tr_bang) { +"abc".tr!("x", "y") }
r(:tr_s_bang) { +"aabbcc".tr_s!("a-c", "x") }
r(:delete_none) { "".delete }
