# ruby 4.1's String#tr and tr! take a Hash (Feature #22238): each key, one
# character, gives way to its value, a String of any length. The result
# takes the encoding that the receiver, the keys and the values agree on.
def t(label)
  r = yield
  puts "#{label}: #{r.inspect} #{r.encoding if r.is_a?(String)}"
rescue Exception => e
  puts "#{label}: #{e.class}: #{e.message}"
end

t("multi") { "hello".tr("e" => "EH! ", "o" => "OH!", "l" => "") }
t("multibyte keys") { "h€llø".tr("€" => "e", "ø" => "o") }
t("into multibyte") { "hello".tr("e" => "é", "o" => "ö") }
t("us-ascii joins") { "hello".encode("US-ASCII").tr("e" => "é") }
t("utf-16") do
  u = ->(s) { s.encode("UTF-16LE") }
  u["h€llø"].tr(u["€"] => u["e"], u["ø"] => u["o"]) == u["hello"]
end
t("binary") { "a\xffb".b.tr("a".b => "\xfe".b) }
t("euc") { "日本".encode("EUC-JP").tr("本".encode("EUC-JP") => "x") }
t("no match") { "hello".tr("z" => "y") }
t("itself") { "hello".tr("l" => "l") }
t("empty hash") { "hello".tr({}) }
t("empty string") { "".tr("a" => "b") }
t("empty string bad") { "".tr(5) }
t("empty value") { "aaa".tr("a" => "") }
t("long key") { "hello".tr("hel" => "") }
t("grapheme key") { "🤦🏼‍♂️".tr("🤦🏼‍♂️" => "") }
t("empty key") { "hello".tr("" => "x") }
t("not a hash") { "hello".tr(["e", "a"]) }
t("nil") { "hello".tr(nil) }
t("int key") { "hello".tr(1 => "x") }
t("int value") { "hello".tr("e" => 1) }
o = Object.new
def o.to_str = "e"
t("to_str key") { "hello".tr(o => "3") }
t("to_str value") { "hello".tr("l" => o) }
t("bad key enc") { "fée".tr("é".encode("ISO-8859-1") => "e") }
t("bad value enc") { "fée".tr("e" => "é".encode("ISO-8859-1")) }
t("mixed enc") { "ab".encode("US-ASCII").tr("a" => "à".encode("ISO-8859-1"), "b" => "é") }
t("ascii from latin1") { "ab".encode("US-ASCII").tr("a" => "à".encode("ISO-8859-1")) }
t("broken") { "a\xffb".tr("a" => "b") }
t("broken empty hash") { "a\xffb".tr({}) }
t("zero args") { "hello".tr }
t("three args") { "hello".tr("a", "b", "c") }
t("two args still") { "hello".tr("el", "ip") }
t("dup keys by value") { "abc".tr({ "a" => "1", "a".encode("US-ASCII") => "2" }) }

s = +"hello"
p s.tr!("l" => "L"), s
p (+"hello").tr!("z" => "y"), (+"hello").tr!({}), (+"").tr!("a" => "b")
t("frozen bang") { "hello".freeze.tr!("z" => "y") }
t("frozen empty bang") { "".freeze.tr!({}) }
t("frozen tr") { "hello".freeze.tr("e" => "a") }
t("bang zero") { (+"x").tr! }
t("bang three") { (+"x").tr!(1, 2, 3) }

class MyStr < String; end
r = MyStr.new("abc").tr("a" => "z")
p r.class, r
p String.instance_method(:tr).arity, String.instance_method(:tr!).arity
p String.instance_method(:tr).parameters, String.instance_method(:tr_s).arity
