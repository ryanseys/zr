# enc_str_scrub returns early only for a coderange that a scan kept: a
# literal, a copy of one, an interned String or a sum of scanned ones. For
# any other String it checks the replacement first, valid bytes or not.
def t(l) = (puts "#{l}: #{yield.inspect}" rescue puts "#{l}: #{$!.class}")
t("lit") { "abc".scrub(1) }
t("inspect") { [].inspect.scrub(1) }
t("inspect scanned") { s = [].inspect; s.valid_encoding?; s.scrub(1) }
t("dup") { "abc".dup.scrub(1) }
t("plus") { ("a" + "b").scrub(1) }
t("to_s") { 12.to_s.scrub(1) }
t("bang lit") { +"abc".scrub!(1) }
t("bang inspect") { [].inspect.scrub!(1) }
t("sym") { :ab.to_s.scrub(1) }
t("interp") { "#{1}x".scrub(1) }
t("nil") { [].inspect.scrub(nil) }
t("frozen valid bang") { [].inspect.freeze.scrub! }
t("broken") { "a\xff".scrub(1) }
t("broken ok") { "a\xff".scrub("?") }
t("block") { "a\xff".scrub { "<#{_1.unpack1("H*")}>" } }
t("plus mixed") { ("é" + "b").scrub(1) }
t("plus scanned") { (12.to_s + "b").scrub(1) }
t("plus broken") { ("a\xff" + "b").scrub("?") }
t("uminus") { (-(12.to_s)).scrub(1) }
