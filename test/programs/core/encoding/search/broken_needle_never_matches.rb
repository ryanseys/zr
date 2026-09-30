# A needle that is not valid in its encoding never matches, as CRuby's
# rb_str_index decides; a prefix or a suffix must end or start on a
# character boundary.
def t = yield rescue [$!.class, $!.message]

s = "é\xA9x"
p t { s.include?("\xA9") }, t { s.index("\xA9") }, t { s.byteindex("\xA9") }, t { s.rindex("\xA9") }
p t { s.partition("\xA9") }, t { "é\xA9x".index("x") }
p t { "é".start_with?("\xC3") }, t { "é".delete_prefix("\xC3") }, t { "aé".end_with?("\xA9") }, t { "aé".delete_suffix("\xA9") }
w = "é\xA9é"
p t { w.index("\xA9") }, t { w.byteindex("\xA9") }, t { "\xA9é".index("\xA9") }, t { w.rindex("é") }, t { w.byterindex("\xA9") }
p t { "aé".start_with?("a") }, t { "aé".end_with?("é") }, t { "aéb".rindex("é") }, t { "ééé".index("é", 1) }

