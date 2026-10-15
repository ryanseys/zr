# Integer(), Float(), Rational() and Complex() read a String's bytes, so
# text with a byte its encoding cannot hold is an invalid value, named
# by inspect, not an invalid byte sequence.
def t
  p yield
rescue => e
  p [e.class, e.message]
end
t { "ok".scrub(1) }
t { "ok".scrub(nil) }
t { "ok".scrub("\xff") }
t { "ok".scrub!(1) }
t { "ok".scrub(1) { "x" } }
t { "\xffa".scrub(1) }
t { Integer("\xff") }
t { Integer("1\xff") }
t { Integer("\xff", exception: false) }
t { Integer("12あ") }
t { Float("\xff") }
t { Rational("\xff") }
t { Complex("\xff") }
t { "\xff".to_i }
t { Complex("1+2i\xff") }
t { Complex(" 3i ".b) }
t { Complex("1@2".encode("US-ASCII")) }
t { Integer(" 0x1F\n".b) }
t { Integer("1_000".encode("EUC-JP")) }
