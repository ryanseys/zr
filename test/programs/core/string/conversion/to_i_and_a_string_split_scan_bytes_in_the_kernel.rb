# String#to_i in base 10 and a split by a String read their bytes in
# the kernel: the same answers as ruby's for blanks, signs,
# underscores, a `0d` prefix, numbers past a fixnum, and for pieces
# with limits, empty pieces, multibyte separators and encodings.
p "42".to_i, " \t\n\v\f\r42".to_i, "-42".to_i, "+42".to_i, "4_2".to_i, "4__2".to_i, "_42".to_i, "42_".to_i, "42abc".to_i, "abc".to_i, "".to_i
p "0d42".to_i, "-0d42".to_i, " 0D42".to_i, "00d42".to_i, "10d".to_i, "0_d5".to_i, "0d".to_i, "0x1f".to_i, "0b101".to_i, "0o17".to_i, "017".to_i
p "9223372036854775807".to_i, "4611686018427387903".to_i, "4611686018427387904".to_i, "-4611686018427387904".to_i, "123456789012345678901234567890".to_i, "000000000000000000000042".to_i
p "1e5".to_i, "1.9".to_i, " 42".to_i, "４２".to_i, "42\0".to_i, "\0 42".to_i, "1_000_000".to_i, "12".to_i(10), "12".to_i(16), "z".to_i(36)
p "a,b,c".split(","), "a,,b,,".split(","), "a,,b,,".split(",", -1), "a,b,c".split(",", 2), "a,b,c".split(",", 1), ",a".split(","), "".split(","), ",".split(",")
p "a--b--c".split("--"), "a--b".split("-"), "abc".split("abc"), "abcabc".split("abc", -1), "aXbXc".split("X", 0), "a b  c".split(" "), "a\tb".split("\t")
p "héllo wörld".split("ö"), "日本語、テキスト、です".split("、"), "日本".split("本", -1), "ab".split("c"), "a,b".split(",", 3), "a,b,c,d".split(",", -2)
p "a,b".split(",").map(&:encoding).uniq, "a,b".b.split(",").first.encoding, "x".encode("UTF-16LE").split("x".encode("UTF-16LE")).size
p (("a,b".split("é".encode("ISO-8859-1"))) rescue $!.class), ("ab".split("\xff") rescue $!.class), "ab".split("b".b)
p "a,b,c".split(",") { |piece| print piece.upcase, " " }, "csv,line,here".split(",").map(&:size)


