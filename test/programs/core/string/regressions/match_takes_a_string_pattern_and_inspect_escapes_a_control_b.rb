# String conformance
p("hello".match?("l"))              # match? String pattern
p("hello".match?("z"))
p("hello".match("l").class)
p("hello".match("z").class)
p("a".gsub("a", "\\\\").bytes)      # doubled backslash collapse
p("ab".gsub("a", "[\\&]"))
p("a.b".sub(".", "\\\\"))
p("\x02".inspect)                   # control byte -> \uNNNN
p("\e".inspect)
p("\a\b\t\n\v\f\r".inspect)
p("\x00\x1c\x7f".inspect)
begin                                # negative codepoint RangeError
  s = "a"; s << -1
  p :no_error
rescue RangeError => e
  p e.class
end
