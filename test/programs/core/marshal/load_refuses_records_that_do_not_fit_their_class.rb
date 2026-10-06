# Marshal.load refuses a record that does not fit the class it names,
# with the TypeError or ArgumentError that marshal.c raises.
def t(name)
  r = yield
  puts "#{name}: #{r.inspect}"
rescue => e
  puts "#{name}: #{e.class}: #{e.message}"
end

class Klass; end
module Mod; end
t("class ivar") { Marshal.load("\x04\x08Ic\x0aKlass\x06:\x0e@ivar_bug\"\x08bug") }
t("module ivar") { Marshal.load("\x04\x08Im\x08Mod\x06:\x0e@ivar_bug\"\x08bug") }
t("linked class ivar") { Marshal.load("\x04\x08[\x07c\x0aKlassI@\x06\x06:\x0e@ivar_bug\"\x08bug") }
p Klass.instance_variable_defined?(:@ivar_bug)

Pair = Struct.new(:foo, :bar)
dump = Marshal.dump(Pair.new("FOO", "BAR"))
Object.send(:remove_const, :Pair)
Pair = Struct.new(:foo)
t("fewer members") { Marshal.load(dump) }
Object.send(:remove_const, :Pair)
Pair = Struct.new(:foo, :baz)
t("other member") { Marshal.load(dump) }
Object.send(:remove_const, :Pair)
Pair = Class.new
t("not a struct") { Marshal.load(dump) }
t("range as struct") { Marshal.load("\x04\bS:\nRange\b:\x06a0:\x06b0:\x06c0") }

class Dumped
  def _dump(_) = "x"
end
dump = Marshal.dump(Dumped.new)
t("no _load") { Marshal.load(dump) }
class Kept
  def marshal_dump = 1
end
t("no marshal_load") { Marshal.load(Marshal.dump(Kept.new)) }

t("complex 0") { Marshal.load("\x04\bU:\fComplex[\x05") }
t("complex 1") { Marshal.load("\x04\bU:\fComplex[\x06i\x00") }
t("complex 2") { Marshal.load("\x04\bU:\fComplex[\ai\x06i\a") }
t("complex 3") { Marshal.load("\x04\bU:\fComplex[\bi\x00i\x00i\x00") }
t("rational 1") { Marshal.load("\x04\bU:\rRational[\x06i\x00") }
t("rational 2") { Marshal.load("\x04\bU:\rRational[\ai\x06i\a") }
t("rational 3") { Marshal.load("\x04\bU:\rRational[\bi\x00i\x00i\x00") }

t("negative bignum length") { Marshal.load("\x04\x08l+\xfc\x00\x00\x00\x80") }
t("long bignum") { Marshal.load("\x04\x08l+\x04\x00\x00\x00\x40") }
t("negative array length") { Marshal.load("\x04\x08[\xfa") }
t("bad link") { Marshal.load("\x04\bI/\x05\x00\x06:\x06E{\x06@\x05T") }
t("broken symbol") { Marshal.load("\x04\bI:\x06K\x06:\x0dencoding\"\x0dUTF-16LE") }
t("old module tag ivar") { Marshal.load("\x04\x08IM\x0aKlass\x06:\x0e@ivar_bug\"\x08bug") }
