# fnmatch matches as dir.c's does: a wildcard takes a newline, a trailing
# backslash matches nothing, a set reads its members as they are, and
# FNM_CASEFOLD folds ASCII alone.
cases = [["*", "\n"], ["?", "\n"], ["a*", "a\nb"], ["\\", "\\"], ["a\\", "a\\"], ["[z-a]", "b"], ["[a\\-c]", "b"],
         ["[a\\-c]", "-"], ["[]a]", "]"], ["[!]", "!"], ["[a-]", "-"], ["\\*", "*"], ["a[", "a["], ["[", "["]]
cases.each { |pattern, path| p [pattern, path, File.fnmatch(pattern, path)] }
p File.fnmatch("É", "é", File::FNM_CASEFOLD), File.fnmatch("A", "a", File::FNM_CASEFOLD)
# bracket reads the case of the byte after a member, as CRuby does.
p File.fnmatch("[abc]", "]", File::FNM_CASEFOLD), File.fnmatch("[^a]", "]", File::FNM_CASEFOLD)
