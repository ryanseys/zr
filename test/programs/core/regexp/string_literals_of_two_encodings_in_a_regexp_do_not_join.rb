# -*- coding: cp932 -*-
# Two String literals of other encodings, one per interpolation, are
# joined when the code is compiled, which raises before the regexp is
# made. A literal fragment beside them gives the regexp error.
def t(name)
  r = yield
  puts "#{name}: #{r.inspect}"
rescue Exception => e
  puts "#{name}: #{e.class}: #{e.message}"
end
t("string pieces") { eval(%q(/#{"\u1234"}#{"あ"}/)) }
t("unicode then sjis") { eval(%q(/\u{1234}#{nil}あ/)) }
t("sjis then unicode") { eval(%q(/あ#{nil}\u1234/)) }
