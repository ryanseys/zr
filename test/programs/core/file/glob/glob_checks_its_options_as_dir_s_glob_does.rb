# glob checks its options as dir_s_glob does.
p((Dir.glob("*", sort: nil) rescue $!), (Dir.glob("*", "x") rescue $!), (Dir.glob("a\0b") rescue $!), (Dir.glob(1) rescue $!))
p Dir.glob("*", base: "").class, (Dir.glob("a".encode("utf-16le")) rescue $!)
