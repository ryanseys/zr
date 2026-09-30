# With FNM_PATHNAME a "**/" takes any number of directories, and a
# hidden one only with FNM_DOTMATCH.
pn = File::FNM_PATHNAME
p File.fnmatch("**/b", "a/x/y/b", pn), File.fnmatch("**/b", "b", pn), File.fnmatch("**/b", ".x/b", pn),
  File.fnmatch("**/b", ".x/b", pn | File::FNM_DOTMATCH), File.fnmatch("*/b", "a/x/b", pn), File.fnmatch("a/**/b", "a/b", pn)
# The pattern is a C string; the path is a path.
p((File.fnmatch("a\0", "a") rescue $!), (File.fnmatch("a", "a\0") rescue $!), (File.fnmatch(:a, "a") rescue $!))
p File.fnmatch("a".encode("utf-16le"), "a"), (File.fnmatch("*", "a".encode("utf-16le")) rescue $!)
p File.fnmatch("あ*".encode("euc-jp"), "あい".encode("euc-jp"))
