# `s[...] = t` on a frozen String converts the index, finds the place and
# converts the replacement first; only a write that would happen raises
# FrozenError.
def try(label)
  yield
  puts "#{label}: no error"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

s = "abc".freeze
try("nil index") { s[nil] = "Q" }
try("float index") { s[1.5] = "Q" }
try("integer index") { s[1] = "Q" }
try("integer index, integer value") { s[1] = 1 }
try("index past the end") { s[9] = "q" }
try("index past the end, integer value") { s[9] = 1 }
try("negative index past the start") { s[-9] = "q" }
try("start and length") { s[1, 1] = "Q" }
try("nil length") { s[1, nil] = "Q" }
try("negative length") { s[1, -1] = "Q" }
try("start past the end") { s[9, 1] = 1 }
try("range") { s[0..1] = "x" }
try("range out of range") { s[5..6] = "x" }
try("range out of range, integer value") { s[5..6] = 1 }
try("range, integer value") { s[0..1] = 2 }
try("substring found") { s["b"] = "x" }
try("substring missing") { s["z"] = "x" }
try("substring, integer value") { s["a"] = 1 }
try("regexp matches") { s[/a/] = "x" }
try("regexp misses") { s[/z/] = "x" }
try("regexp, integer value") { s[/a/] = 1 }
try("regexp group out of range") { s[/a/, 9] = "x" }
try("regexp group not matched") { s[/(z)?a/, 1] = "x" }
try("incompatible encoding") { s[0] = "\xff".force_encoding("UTF-16LE") }
try("one argument") { s.send(:[]=, 1) }

t = +"abc"
t[1] = "Q"
t[0..0] = "x"
t[/c/] = "C"
p t, t.frozen?
