# ruby 4.1's MatchData#integer_at (Feature #21932) reads a group as
# rb_int_parse_cstr does: its leading number in a base, or nil where
# it has none. A missing group, or one that did not take part, is nil.
m2 = /(\d+)-(\w+)(z)?/.match("abc 42-ff")
p m2.integer_at(0), m2.integer_at(1), m2.integer_at(2, 16), m2.integer_at(3), m2.integer_at(-2, 16), m2.integer_at(-3)
p m2.integer_at(-4), m2.integer_at(-5), m2.integer_at(9, 1), m2.integer_at(1, 36), m2.integer_at(1, 0)
def t(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message.sub(/0x\h+/, "0xX")}"
end
m = /(\d+)-(?<x>\w+)?(z)?/.match("abc 42-ff")
t("0") { m.integer_at(0) }
t("1") { m.integer_at(1) }
t("x") { m.integer_at(:x) }
t("x str") { m.integer_at("x") }
t("x 16") { m.integer_at(:x, 16) }
t("unmatched") { m.integer_at(3) }
t("past") { m.integer_at(4) }
t("neg") { m.integer_at(-1) }
t("neg2") { m.integer_at(-2) }
t("neg all") { m.integer_at(-4) }
t("neg past") { m.integer_at(-5) }
t("bad name") { m.integer_at(:nope) }
t("bad type") { m.integer_at(1.5) }
t("nil") { m.integer_at(nil) }
t("radix neg") { m.integer_at(1, -1) }
t("radix 1") { m.integer_at(1, 1) }
t("radix 37") { m.integer_at(1, 37) }
t("radix 0") { m.integer_at(1, 0) }
t("radix 2") { m.integer_at(1, 2) }
t("radix str") { m.integer_at(1, "8") }
t("none") { m.integer_at }
t("three") { m.integer_at(1, 2, 3) }
[" 12", "12 ", "-12", "+12", "1_000", "1__0", "_1", "0x1f", "0b101", "0o17", "017", "12abc", "abc", "", "  ", "-", "0_8",
 "99999999999999999999999", "１２", "1e3", "0x", "--1"].each do |s|
  md = /\A(.*)\z/m.match(s)
  t(s.inspect) { [md.integer_at(1), md.integer_at(1, 16), md.integer_at(1, 0)] }
end
t("big index") { m.integer_at(2**64) }
o = Object.new
def o.to_int = 1
t("to_int idx") { m.integer_at(o) }
t("to_int radix") { m.integer_at(1, o) }
t("arity") { MatchData.instance_method(:integer_at).arity }
