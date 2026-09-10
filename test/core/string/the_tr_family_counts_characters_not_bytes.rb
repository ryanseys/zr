# tr, tr_s, count, delete and squeeze read a spec as characters, so a
# multibyte character is one member of the set and one place in the
# replacement. A range spans codepoints.
p "あいう".tr("い", "X")
p "あいう".tr("あ-う", "A-C")
p "あいあいあ".count("あ")
p "あいあいあ".delete("い")
p "ああいいうう".squeeze
p "あいう".count("^あ")
p "あいう".delete("^あ")
p "あいあ".squeeze("あ")
p "\u{1F600}b".tr("\u{1F600}", "X")
p "あああいいい".tr_s("あい", "AI")

# The ASCII rules are unchanged.
p "hello".tr("el", "ip")
p "abc".tr("aa", "XY")
p "abc".tr("^a", "Z")
p "abc".tr("a-", "X")
p "a-c".tr("\\-", "X")
p "abc".tr("a", "")
p "abc".tr("^", "X")
p "abcdef".tr("a-cd", "1-4")
p "abc".count("a-c", "^b")
begin
  "abc".tr("c-a", "X")
rescue ArgumentError => e
  p e.message
end
begin
  "abc".count(1)
rescue TypeError => e
  p e.message
end
__END__
"あXう"
"ACC"
3
"あああ"
"あいう"
2
"あ"
"あいあ"
"Xb"
"AI"
"hippo"
"Ybc"
"aZZ"
"Xbc"
"aXc"
"bc"
"abc"
"1234ef"
2
"invalid range \"c-a\" in string transliteration"
"no implicit conversion of Integer into String"
