# strscan 3.1.9 (ruby 4.1): no ScanError or Id, integer_at, no match
# from inside a character, and a string that shrank after a match
# cuts the match, its groups, charpos and matched_size at its end.
require "strscan"
def t; p yield; rescue => e; p [e.class, e.message]; end
t { defined?(ScanError) }
t { StringScanner.const_defined?(:Id) }
t { StringScanner.constants.sort }
t { StringScanner::Version }
s = StringScanner.new("abc")
t { s.scan(/(a)(b)/); s.scan("c"); [s.size, s.captures] }
s = StringScanner.new("abc")
t { s.scan(/(a)(b)/); s.getch; [s.size, s.captures] }
s = StringScanner.new("abc")
t { s.scan(/(a)(b)/); s.get_byte; [s.size, s.captures] }
u = StringScanner.new("ab".encode("UTF-16BE"))
u.pos = 1
t { [u.scan(/./), u.check(/./), u.match?(/./), u.exist?(/./), u.skip(/./), u.search_full(/./, false, false)] }
u.pos = 0
t { u.scan(/./)&.bytes }
w = StringScanner.new("héllo")
w.pos = 2
t { [w.scan(/./), w.pos, w.charpos] }
x = StringScanner.new("hello world")
x.scan(/hello /)
x.string.replace("hi")
t { [x.charpos, x.eos?, x.matched_size, x.rest, x.pos] }
y = StringScanner.new("ab12")
y.scan(/(ab)(\d*)/)
t { [y.integer_at(2), y.integer_at(1)] }
z = StringScanner.new("ab")
z.scan(/(a)()/)
t { z.integer_at(2) }
q = StringScanner.new("abcdef")
q.scan(/(abc)(def)/)
q.string.replace("ab")
t { [q.integer_at(0), q[1], q[2], q.matched_size, q.pre_match, q.post_match] }
def ia(str, re, *a)
  s = StringScanner.new(str)
  s.scan(re)
  p [str, a, (begin; s.integer_at(*a); rescue => e; [e.class, e.message]; end)]
end
ia("12abc", /(\w+)/, 1)
ia(" 12", /(.+)/, 1)
ia("-0x1f", /(.+)/, 1, 16)
ia("0x1f", /(.+)/, 1)
ia("1_000", /(.+)/, 1)
ia("1__0", /(.+)/, 1)
ia("+7", /(.+)/, 1)
ia("ff", /(.+)/, 1, 16)
ia("12", /(?<n>\d+)/, "n")
ia("12", /(?<n>\d+)/, :n)
ia("12", /(\d+)/, 5)
ia("12", /(\d+)/, -1)
ia("12", /(\d+)/, "x")
ia("0b101", /(.+)/, 1, 0)
ia("12", /(\d+)/, 1, 99)
ia("1e5", /(.+)/, 1)
ia("０", /(.+)/, 1)
ia("-0", /(.+)/, 1)
ia("ab", /(a)(x)?/, 2)
s = StringScanner.new("12")
p s.integer_at(0)
s.scan(/x/)
p s.integer_at(0)
s.getch
p s.integer_at(0)
p s.scan_integer
s = StringScanner.new("-42 0x1F")
p [s.scan_integer, s.scan(/ /), s.scan_integer(base: 16)]
