# undump reverses dump, in every encoding dump writes, and raises what
# str_undump raises.
cases = ['"\\u{110000}"', '"\\uD800"', '"\\u12"', '"\\u"', '"\\u{zz}"', '"\\u{1234567}"', '"\\c"', '"a', '"a\\', '"\\u{41',
         '"x".dup.force_encoding("EUC-JP")', '"x".force_encoding("Nope")', '"\\u3042".force_encoding("EUC-JP")', '"\\xff\\u3042"',
         '"\\x7f\\u3042"', '"a"'.encode("utf-16le"), "\"a\0\""]
cases.each { |c| p [c, (c.undump rescue $!)] }
["é".encode("utf-16le"), "é".encode("utf-32be"), "é".dup.force_encoding("utf-16"), "あ".encode("sjis")].each { |s| p s.dump.undump == s }
