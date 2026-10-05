# String methods check their receiver and arguments in CRuby's order.
def show
  p yield
rescue => e
  p [e.class, e.message]
end

show { "あ".encode("ISO-2022-JP").rstrip }
show { "あ".encode("ISO-2022-JP").strip }
show { "あ\u0000 ".rstrip }
show { "".freeze.replace(42) }
show { "a".dup.slice! }
show { "a,b".split(BasicObject.new) }
show { "a,b".split(",") }

got = []
"00".upto("03") { |s| got << [s, s.encoding] }
p got

show { "\xe3\x81\x82".delete_prefix("\xe3") }
show { "\x95\x5c".dup.force_encoding("Shift_JIS").delete_prefix("\x95") }
show { "\xFF\xFE".delete_prefix("\xFF") }
show { "\xFFhello\xBE".delete_prefix("\xFFhello") }
show { "\xFF\xFE".dup.delete_prefix!("\xFF") }
show { "hello".delete_prefix("he") }

p "".hash == "".encode(Encoding::UTF_32BE).hash
h = { "" => 1 }
p h["".encode(Encoding::UTF_32BE)]

show { "mypassword".crypt("aa".encode("UTF-16LE")) }
show { "mypassword".encode("UTF-32BE").crypt("aa") }

r = Regexp.new("foo")
def r.match(x, y, z) = x + y + z
show { "foo".match(r, "bar", "baz") }
show { "foo".match }
show { "foobarbaz".match(/bar/).to_s }

a = "abc".dup.force_encoding(Encoding::US_ASCII)
p a.tr("z", "ā").encoding
p a.tr("a", "ā").encoding
p "ABC".tr("A-AB", "XY")
p "ぁ".tr("ぁ", "a").ascii_only?

o = Object.new
def o.to_s = self
p "foobarbaz".sub("bar") { o }.sub(/0x\h+/, "0x")

show { "0".encode("UTF-16BE").to_i }
show { "0".encode("ISO-2022-JP").to_i }
show { "12".to_i }

got = []
"".split(//, 1) { |x| got << x }
p got
"a b".split(" ", 1) { |x| got << x }
p got
s = "abc " * 20
show { s.split { s.prepend("xxx") } }
