# File.dirname, split, realpath, realdirpath and expand_path give a path
# in the encoding of the path they were given, as ruby 4.1 does: "." and
# "/" too, a realpath whose bytes do not convert is forced into it, and a
# relative path of ASCII bytes joined to a directory takes the directory's.
$stdout.sync = true
dir = File.join(Dir.pwd, "realpath_あ_#{$$}")
Dir.mkdir(dir)
f = File.join(dir, "file.txt")
File.write(f, "x")
e = f.encode("EUC-JP")
p File.dirname(e).encoding, File.split(e).map(&:encoding), File.basename(e).encoding, File.extname(e).encoding
p File.dirname("/a/b".encode("EUC-JP")).encoding, File.dirname("b".encode("EUC-JP")).encoding, File.dirname("/".encode("EUC-JP")).encoding
p File.realpath(e).encoding, File.realdirpath(e).encoding
p File.realpath("file.txt".encode("EUC-JP"), dir.encode("EUC-JP")).encoding
p File.realdirpath("file.txt".encode("EUC-JP"), dir.encode("EUC-JP")).encoding
r = File.realpath(".".encode("ISO-8859-1"), dir)
p r.encoding, r.b.include?(dir.b)
r = File.realdirpath(".".encode("ISO-8859-1"), dir)
p r.encoding, r.b.include?(dir.b), r.valid_encoding?
p File.expand_path("x".encode("EUC-JP"), "/tmp").encoding, File.absolute_path("x".encode("EUC-JP"), "/tmp").encoding
File.delete(f)
Dir.rmdir(dir)
e = ->(s) { s.encode("EUC-JP") }
[-> { File.expand_path(e.("x"), "/tmp") }, -> { File.expand_path(e.("é"), "/tmp") }, -> { File.expand_path(e.("/x")) },
 -> { File.expand_path(e.("x"), e.("/tmp")) }, -> { File.expand_path("x", e.("/tmp")) }, -> { File.expand_path(e.("x")) },
 -> { File.absolute_path(e.("/x")) }, -> { File.expand_path("x".b, "/tmp") }, -> { File.expand_path("é".encode("ISO-8859-1"), "/tmp") },
 -> { File.expand_path(e.("/x"), "/tmp") }, -> { File.absolute_path(e.("x"), "/tmp") }].each do |f|
  p f.call.encoding
rescue => error
  p error.class
end

# An ASCII-only path in another encoding comes back in it from
# realpath and realdirpath, given alone or with a directory.
here = File.expand_path(__FILE__).encode("EUC-JP")
where = File.dirname(File.expand_path(__FILE__)).encode("EUC-JP")
p File.realdirpath(here).encoding, File.realpath(here).encoding
p File.realdirpath(File.basename(here), where).encoding, File.realpath(File.basename(here), where).encoding
p File.realdirpath("missing".encode("EUC-JP"), where).encoding
