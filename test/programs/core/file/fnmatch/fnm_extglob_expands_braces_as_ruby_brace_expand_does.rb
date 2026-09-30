# FNM_EXTGLOB expands braces as ruby_brace_expand does: a backslash hides
# a brace or a comma, and a brace that never closes gives no pattern.
e = File::FNM_EXTGLOB
p File.fnmatch("{a,b}", "b", e), File.fnmatch("{a,b", "{a,b", e), File.fnmatch("\\{a}", "{a}", e),
  File.fnmatch("{a\\,b}", "a,b", e), File.fnmatch("{a,{b,c}}", "c", e), File.fnmatch("{,a}", "", e),
  File.fnmatch("{a,b}", "{a,b}", e | File::FNM_NOESCAPE)
