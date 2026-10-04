# String methods convert offsets through to_int and strings through
# to_str first, as CRuby does; bytesplice takes all its forms with the
# checks of str_check_beg_len; [] and slice! raise where CRuby raises.
def t
  yield
rescue => e
  [e.class, e.message]
end
i = Object.new
def i.to_int = 1
s = Object.new
def s.to_str = "l"
class MyS < String; end
h = "hello"
p t { h[1, nil] }, t { h[nil, 1] }, t { h[1..2, 1] }, t { h[/(l)/, nil] }, t { h[i, i] }, t { h[MyS.new("el")].class }
p t { "x".freeze.slice!(5) }, t { "x".freeze.slice!(/z/) }
p t { h.index("l", i) }, t { h.rindex(s, i) }, t { h.byteindex("l", i) }, t { h.byterindex(s, 4) }, t { h.rindex("l", nil) }
"a" =~ /a/; h.index(/l/, 99); p $~
h.byteindex(/l/); p $~[0]
h.byteindex(/z/); p $~
p t { h.dup.insert(i, s) }, t { h.dup.insert(1, 5) }, t { h.sum(i) }, t { h.delete_prefix(s) }, t { "hel".delete_suffix(s) }, t { h.partition(s) }, t { h.rpartition(s) }
def t(s, *a)
  r = s.dup
  r.bytesplice(*a)
  r
rescue => e
  [e.class, e.message]
end
s = "hello"
p t(s, 2, "xx"), t(s, 1..2), t(s, 1..2, "xx"), t(s, 1, 2, "xx"), t(s, 1, 2, "xyz", 1, 1), t(s, 1..2, "xyz", 1..1)
p t(s, -6, 1, "x"), t(s, 6, 1, "x"), t(s, 1, -1, "x"), t(s, 1, 1, "xyz", 4, 1), t(s, 1, 1, "xyz", 1, -1), t(s, 1, 1, "xyz", -4, 1)
p t(s, -7..1, "x"), t(s, 1..2, "xyz", -5..1), t(s, 1, 2, "xyz", 1), t(s, 1..2, "xyz", 1)
p t("", 0, 0, "xyz", 1, 2), t("", 0..0, "xyz", 0..1)
p(("x".freeze.bytesplice(0, 1, "y") rescue $!.class))
m = "あいうえ"
p t(m, 2, 1, "x"), t(m, 3, 3, "x"), t(m, 3, 4, "x"), t(m, 3...6, "x"), t(m, 3..-1, "x"), t(m, 3, 3, "かきく", 3, 3), t(m, 3, 3, "かきく", 2, 3), t(m, 3, 3, "かきく", 3, 2)
p t(m, 6..3, "x"), t(m, 3, 3, "かきく", 3..1)
p t(m, 3, 3, "x".encode("US-ASCII")), t(m, 3, 3, "\xff".b) 
