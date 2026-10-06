# parse.y's rule for a def's parenthesized parameters sets the lexer state
# to BEG, so the space after the closing paren lexes as BEG. Other spaces
# keep the state of the token before them.
require "ripper"
srcs = ["def m(a) nil end", "def m() nil end", "def m(a)\n  nil\nend", "def m(a) # c\nend", "def m(a = (1), b) a end", "def self.m(a) a end",
        "def m (a) a end", "def m a, b = (1)\n a\nend", "def m(a) = a", "def +(o) o end", "foo(a) b", "def m(a) (a) end", "x = def m(a) a end"]
srcs.each { |s| p Ripper.lex(s).map { |(pos, ev, tx, st)| [pos, ev, tx, st.to_s] } }
