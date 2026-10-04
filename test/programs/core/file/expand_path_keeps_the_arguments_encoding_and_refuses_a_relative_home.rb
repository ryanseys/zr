# File.expand_path returns the argument's encoding, refuses a working
# directory in an encoding that is not ASCII compatible, and refuses a
# HOME that is not absolute.
Encoding.default_external = Encoding::SHIFT_JIS
path = "./a".dup.force_encoding Encoding::CP1251
p File.expand_path(path).encoding
p File.expand_path([222, 173, 190, 175].pack('C*')).encoding
Encoding.default_external = Encoding::UTF_16BE
p((File.expand_path("./a") rescue $!.class))
Encoding.default_external = Encoding::UTF_8
h = ENV["HOME"]
ENV["HOME"] = ""
p((File.expand_path("~") rescue [$!.class, $!.message]))
ENV["HOME"] = "non-absolute"
p((File.expand_path("~") rescue [$!.class, $!.message]))
ENV["HOME"] = h
p File.expand_path("a".dup.force_encoding("US-ASCII")).encoding, File.expand_path("/x/../y".b).encoding
p File.expand_path("/a".dup.force_encoding("US-ASCII")).encoding, File.expand_path("a".dup.force_encoding("EUC-JP")).encoding
