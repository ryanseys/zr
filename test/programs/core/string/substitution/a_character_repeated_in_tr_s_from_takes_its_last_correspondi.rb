# A char repeated in `from` takes its LAST corresponding `to` char
# (CRuby's rule), not the FIRST one.

p "a___b".tr("___", ".+-")
p "abcaa".tr("aa", "xy")
p "abcd".tr("abc", "x")
