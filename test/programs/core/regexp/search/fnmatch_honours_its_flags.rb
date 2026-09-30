# `File.fnmatch` honours every flag it accepts.
#
# `FNM_EXTGLOB` expands `{a,b}`, and `FNM_PATHNAME` stops `*` at a `/`, so
# "is this path inside one directory" gets no for a nested path.
#
# It also follows CRuby's other rules: the leading-DOT rule (`fnmatch("*", ".x")` is false without
# `FNM_DOTMATCH`), backslash escapes (`FNM_NOESCAPE` turns them off),
# bracket RANGES (`[a-c]`), and a `]` in the first position of a set,
# which ends the set in `fnmatch` where glob reads it as a member.

p File.fnmatch("{a,b}.rb", "b.rb", File::FNM_EXTGLOB)
p File.fnmatch("{a,{b,c}}.rb", "c.rb", File::FNM_EXTGLOB)
p File.fnmatch("{a,b}.rb", "b.rb")
p File.fnmatch("*", "a/b", File::FNM_PATHNAME)
p File.fnmatch("a/*", "a/b", File::FNM_PATHNAME)
p File.fnmatch("*", ".x", File::FNM_DOTMATCH)
p File.fnmatch("A*", "abc", File::FNM_CASEFOLD)
p File.fnmatch("[[:alpha:]]", "a")
p File.fnmatch("a?c", "abc")
