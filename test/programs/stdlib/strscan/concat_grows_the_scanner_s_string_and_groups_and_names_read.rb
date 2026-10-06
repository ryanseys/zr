# concat grows the scanner's own string; a number counts groups from the
# end; a name needs a Regexp's groups, and named_captures reads the names
# of the last Regexp tried.
require "strscan"
x = +"ab"
s = StringScanner.new(x)
s << "cd"
p [x, s.string.equal?(x), s.scan(/abcd/)]
s = StringScanner.new("abc")
s.scan("ab")
p [s[-1], s[0], s[1], s[-2], (s[:x] rescue $!)]
s = StringScanner.new("abc")
s.scan(/(?<a>x)/)
p s.named_captures
s.scan(/(?<a>a)(?<b>b)?/)
p [s.named_captures, s[:a], s["b"], (s[:zz] rescue $!), s[-1], s[-3]]
s.scan("c")
p s.named_captures
