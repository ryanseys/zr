# Marshal keeps what ruby keeps through a dump and a load: the encoding
# of a string at the depth limit, a ruby2_keywords flag, a NameError's
# name, a symbol that a link inside its own ivars names, a Range
# subclass and a Range that holds itself, and an extended or prepended
# singleton class.
def t(name)
  r = yield
  puts "#{name}: #{r.inspect}"
rescue => e
  puts "#{name}: #{e.class}: #{e.message}"
end

t("limit 1 utf-8") { Marshal.load(Marshal.dump("\u3042", 1)) }
t("limit 2 nested") { Marshal.dump([[[]]], 2) }
t("limit 3 nested") { Marshal.load(Marshal.dump([[[]]], 3)) }

class Clearer
  def initialize(list) = @list = list
  def _dump(_)
    @list.clear
    "x"
  end
end
list = []
list << Clearer.new(list) << nil
t("array changed during dump") { Marshal.dump(list) }

def r2k(*args) = args.last
ruby2_keywords :r2k
flagged = r2k(key: 42)
t("flag kept") { Hash.ruby2_keywords_hash?(Marshal.load(Marshal.dump(flagged))) }
t("flag dumped") { Marshal.dump(flagged).include?(":\x06KT") }
t("flag on non-hash") { Marshal.load("\x04\bI[\x00\x06:\x06KT") }

begin
  undefined_name_here
rescue NameError => e
  copy = Marshal.load(Marshal.dump(e))
  t("name error name") { copy.name }
  t("name error message") { copy.message.lines.first.chomp == e.message.lines.first.chomp }
end

t("symlink in symbol ivars") do
  Marshal.load("\x04\x08I:\x0bKernel\x06I:\x07@a\x06:\x07@be;\x00o:\x0bObject\x000")
end

class MyRange < Range
  def initialize(v, *args)
    super(*args)
    @v = v
  end
end
t("range subclass") do
  r = Marshal.load(Marshal.dump(MyRange.new(4, 5, 8, false)))
  [r.class, r, r.instance_variable_get(:@v)]
end
class CyclicRange < Range
  def <=>(other) = true
end
t("cyclic range") do
  o = CyclicRange.allocate
  o.instance_eval { initialize(o, o) }
  c = Marshal.load(Marshal.dump(o))
  [c.class, c.begin.equal?(c), c.end.equal?(c)]
end

module Mod1; end
class Holder
  def initialize(v) = @v = v
  attr_reader :v
end
t("prepended singleton") do
  o = Holder.new(42)
  o.singleton_class.class_eval { prepend Mod1 }
  c = Marshal.load(Marshal.dump(o))
  [c.v, c.singleton_class.ancestors.take(3).map { _1 == c.singleton_class ? :singleton : _1 }]
end
t("singleton with a method") do
  o = Object.new
  def o.m = nil
  Marshal.dump(o)
end
t("singleton holding a class") do
  o = Object.new
  c = class << o
    @v = 1
    class C; self; end
  end
  [(Marshal.dump(o) rescue $!.class), (Marshal.dump(c) rescue $!.class)]
end

t("regexp escapes of 1.8") { Marshal.load("\004\b/\fa\\u3042\000") }
t("regexp kept escape") { Marshal.load("\004\b/\b\\\\u\000") }
t("regexp lone u") { Marshal.load("\004\b/\a\\u\000") }
t("regexp encoded u") { Marshal.load("\004\bI/\a\\u\000\006:\016@encoding\"\vEUC-JP") }
t("regexp utf-8 escape") { Marshal.load(Marshal.dump(/a\u3042/)) }

begin
  nil.no_such_method_here(1)
rescue NoMethodError => e
  copy = Marshal.load(Marshal.dump(e))
  t("no method error parts") { [copy.name, copy.args, copy.private_call?] }
end
t("key error parts") { c = Marshal.load(Marshal.dump(KeyError.new("m", receiver: 1, key: 2))); [c.receiver, c.key] }

utf8 = eval("class R\u{e9}sum\u{e9}; self; end")
t("non-ascii class") { Marshal.load(Marshal.dump(utf8)).equal?(utf8) }
t("ARGF") { Marshal.dump(ARGF) }
t("old module tag names a class") { Marshal.load("\x04\bM\x0bObject") }

def r2k2(*args) = args.last
ruby2_keywords :r2k2
data = Marshal.dump(r2k2(key: 42))
utf7 = data.sub(/:\x06K(?=T\z)/) { "I#{$&}\x06:\x0dencoding\"\x0aUTF-7" }
t("flag named in another encoding") { Hash.ruby2_keywords_hash?(Marshal.load(utf7)) }
