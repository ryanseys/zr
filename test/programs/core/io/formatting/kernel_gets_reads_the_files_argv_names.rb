
# A bare `gets` reads ARGF, not standard input: the files ARGV names,
# one after another, with $. counting the lines across all of them.
# $< is that same stream.
p $<.equal?(ARGF)
p gets
p $.
p readline
p $.
p readlines
p gets
p $.
p ARGF.class.to_s

