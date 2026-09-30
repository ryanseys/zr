# casecmp folds ASCII alone and casecmp? folds all of Unicode, as
# CRuby's str_casecmp and str_casecmp_p do. An operand the receiver has
# no encoding in common with answers nil.
def t = yield rescue [$!.class, $!.message]

p t { "Ä".casecmp("ä") }, t { "Ä".casecmp?("ä") }, t { "ß".casecmp?("ss") }, t { "ﬃ".casecmp?("ffi") }
p t { "abc".casecmp("ABD") }, t { "b".casecmp("A") }, t { "a".casecmp(1) }, t { "a".casecmp?(1) }
p t { "İstanbul".downcase(:turkic) }, t { "Iı".swapcase(:turkic) }, t { "ΣΑΣ".downcase(:fold) }
p t { "é".casecmp("É".b) }, t { "a".casecmp("A".b) }, t { "é".casecmp?("É") }

